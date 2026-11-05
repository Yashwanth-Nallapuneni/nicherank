#!/usr/bin/env ruby
# frozen_string_literal: true
require 'zlib'
require_relative 'lib/nicherank'

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  manual = File.join(root, 'db/data/manual')
  universities = NicheRank.read_csv(File.join(manual, 'universities.csv'))
  schools = universities.to_h { |u| [u['name'], u] }
  roster = NicheRank.read_csv(File.join(manual, 'faculty_raw.csv')).to_h { |r| [[r['university'], r['name']], r] }
  matches = NicheRank.read_csv(File.join(manual, 'accepted_author_matches.csv'))
  aliases = NicheRank.read_csv(File.join(manual, 'accepted_author_aliases.csv'))
  cutoff = '2026-11-04'
  required = (matches.map { |m| m['openalex_id'] } + aliases.map { |a| a['alias_openalex_id'] }).to_set
  manifests = Dir[File.join(root, 'tmp/work_batches/*.manifest.json')].map { |f| [f, JSON.parse(File.read(f))] }.select { |_, m| m['cutoff'] == cutoff }
  covered = manifests.flat_map { |_, m| m.fetch('author_ids') }.to_set
  raise "Uncollected author IDs: #{(required - covered).size}" unless (required - covered).empty?
  missing_metadata = required.reject { |id| File.exist?(File.join(root, "tmp/author_metadata/#{id}.json")) }
  raise "Missing author metadata: #{missing_metadata.size}" unless missing_metadata.empty?
  professors = matches.map do |match|
    person = roster.fetch([match['university'], match['name']])
    id = match.fetch('openalex_id')
    metadata = JSON.parse(File.read(File.join(root, "tmp/author_metadata/#{id}.json")))
    author = metadata.fetch('author')
    years = [metadata['first_pub_year']] + aliases.select { |a| a['professor_openalex_id'] == id }.map { |a| JSON.parse(File.read(File.join(root, "tmp/author_metadata/#{a['alias_openalex_id']}.json")))['first_pub_year'] }
    { 'openalex_id' => id, 'name' => person['name'], 'university_openalex_id' => schools.fetch(person['university'])['openalex_id'],
      'title' => person['title'], 'homepage_url' => person['homepage_url'], 'orcid' => author['orcid'], 'first_pub_year' => years.compact.min,
      'works_count' => author['works_count'], 'h_index' => author.dig('summary_stats', 'h_index'), 'match_confidence' => match['match_confidence'] }
  end
  works = {}
  manifests.each_with_index do |(file, manifest), index|
    path = file.delete_suffix('.manifest.json')
    raise 'Corrupt completed work batch' unless Digest::SHA256.file(path).hexdigest == manifest.fetch('sha256')
    Zlib::GzipReader.open(path) do |reader|
      reader.each_line do |line|
        work = JSON.parse(line)
        if (existing = works[work.fetch('id')])
          existing['authorships'] = (existing.fetch('authorships') + work.fetch('authorships')).uniq { |a| a.dig('author', 'id') }
        else
          works[work.fetch('id')] = work
        end
      end
    end
    puts "Read #{index + 1}/#{manifests.size} batches; #{works.size} unique raw works"
    $stdout.flush
  end
  extra = NicheRank.read_csv(File.join(manual, 'review.csv')) + NicheRank.read_csv(File.join(manual, 'identity_review_remaining.csv'))
  extra << { 'issue_type' => 'faculty_exclusion', 'university' => 'Georgia Institute of Technology', 'name_or_venue' => 'Alberto Apostolico (1948-2015)', 'candidate_ids' => nil,
             'reason' => 'Directory includes a deceased faculty memorial; excluded from current eligible faculty', 'status' => 'closed', 'resolution' => 'Excluded; raw source entry retained for traceability' }
  works.each_value do |work|
    begin
      NicheRank.abstract(work['abstract_inverted_index'])
    rescue ArgumentError
      extra << { 'issue_type' => 'malformed_abstract', 'university' => nil, 'name_or_venue' => work['title'], 'candidate_ids' => work['id'],
                 'reason' => 'Malformed source inverted index; abstract stored as NULL', 'status' => 'closed', 'resolution' => 'Title and other metadata retained' }
      work['abstract_inverted_index'] = nil
    end
  end
  output = File.join(root, 'data/output/full')
  exporter = NicheRank::Exporter.new(universities: universities, professors: professors, aliases: aliases, works: works.values,
    tiers: NicheRank.read_csv(File.join(manual, 'venue_tiers.csv')), cutoff: cutoff, keep_empty_professors: true)
  manifest = exporter.export(output, scope: 'ten_school_available_profiles', extra_review: extra)
  manifest.merge!('database_schema_version' => 2, 'per_person_paper_cap' => nil, 'faculty_roster_entries' => roster.size,
    'eligible_faculty_after_memorial_exclusion' => roster.size - 1, 'unresolved_author_identities' => NicheRank.read_csv(File.join(manual, 'identity_review_remaining.csv')).size,
    'complete_ten_school_dataset' => false, 'collection_finished_for_all_accepted_profiles' => true,
    'identity_review' => 'Institutional/name matches plus documented manual corrections; not individually human-verified for every automated match.',
    'search_weights' => { 'title' => 'A', 'keywords' => 'A', 'primary_topic' => 'B', 'abstract' => 'C' },
    'database_paper_type_mapping' => { 'proceedings-article' => 'conference-paper' },
    'manual_input_sha256' => Dir[File.join(manual, '*.csv')].sort.to_h { |f| [File.basename(f), Digest::SHA256.file(f).hexdigest] },
    'raw_batch_manifests' => manifests.map { |_, m| m }, 'export_sha256' => Dir[File.join(output, '*.csv')].sort.to_h { |f| [File.basename(f), Digest::SHA256.file(f).hexdigest] })
  manifest['limitations'] += ['Unresolved author identities are explicitly withheld; this is not a claim of 100% faculty coverage.',
    'OpenAlex profiles can contain misattributions or omit publications. Identified suspicious identities are withheld; source errors may remain.',
    'Different-ORCID split candidates are not automatically merged. Only verified aliases contribute papers.',
    'Career works_count and h_index describe the canonical OpenAlex profile; they are not a sum of split profiles.',
    'Generic book series, repositories, workshops, findings and unverified venues do not inherit a parent conference rank.']
  NicheRank.atomic_json(File.join(output, 'manifest.json'), manifest)
  puts JSON.pretty_generate(manifest.slice('counts', 'abstract_coverage_percent', 'unresolved_author_identities', 'dropped_records'))
end
