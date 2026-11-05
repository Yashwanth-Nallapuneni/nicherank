#!/usr/bin/env ruby
# frozen_string_literal: true

# Build the real, bounded, key-free import sample from saved public responses.
# This command is OFFLINE. It never invents missing author IDs or publications.
require_relative 'lib/nicherank'

root = File.expand_path('../..', __dir__)
source = File.join(root, 'tmp/public_sources')
manual = File.join(root, 'db/data/manual')
output = File.join(root, 'db/data/sample')
selected = JSON.parse(File.read(File.join(source, 'sample_selected_candidates.json')))
roster = NicheRank.read_csv(File.join(manual, 'faculty_raw.csv'))
matches = NicheRank.read_csv(File.join(manual, 'author_matches.csv'))
aliases = NicheRank.read_csv(File.join(manual, 'author_aliases.csv'))
approved = matches.select { |m| m['status'] == 'verified' }.to_h { |m| [m['openalex_id'], m] }
professors, works, source_dates = [], [], []
selected.each do |person|
  id = person.fetch('id')
  match = approved.fetch(id) { raise "No reviewed match for sample author #{person['name']}" }
  faculty = roster.find { |p| p['university'] == match['university'] && p['name'] == match['name'] }
  raise 'Sample professor missing from eligible roster' unless faculty
  index = person.fetch('index')
  author = JSON.parse(File.read(File.join(source, "sample_author_#{index}.html"))).fetch('results').find { |a| a['id'].end_with?("/#{id}") }
  raise 'Reviewed author not present in source response' unless author
  profile_keys = [index.to_s]
  profile_keys << 'emma_alias' if person['name'] == 'Emma Brunskill'
  profile_keys << 'guibas_alias' if person['name'] == 'Leonidas Guibas'
  years = profile_keys.filter_map do |key|
    earliest = JSON.parse(File.read(File.join(source, "sample_earliest_#{key}.html"))).fetch('results').first
    earliest && earliest['publication_year']
  end
  professors << { 'openalex_id' => id, 'name' => faculty['name'], 'university_openalex_id' => 'I97018004', 'title' => faculty['title'],
                  'homepage_url' => faculty['homepage_url'], 'orcid' => author['orcid'], 'first_pub_year' => years.min,
                  'works_count' => author['works_count'], 'h_index' => author.dig('summary_stats', 'h_index'), 'match_confidence' => match['match_confidence'] }
  profile_keys.each do |key|
    works.concat(JSON.parse(File.read(File.join(source, "sample_works_#{key}.html"))).fetch('results'))
    %W[sample_works_#{key} sample_earliest_#{key}].each do |stem|
      source_dates << JSON.parse(File.read(File.join(source, "#{stem}.meta.json")))
    end
  end
end
universities = NicheRank.read_csv(File.join(manual, 'universities.csv'))
review = NicheRank.read_csv(File.join(manual, 'review.csv'))
exporter = NicheRank::Exporter.new(universities: universities, professors: professors, aliases: aliases, works: works,
                                 tiers: NicheRank.read_csv(File.join(manual, 'venue_tiers.csv')), cutoff: '2026-11-04')
manifest = exporter.export(output, scope: 'bounded_real_import_sample', extra_review: review)
manifest.merge!('complete_ten_school_dataset' => false, 'faculty_sample_universities' => ['Stanford University'],
                'publication_sample_limit' => 'At most two recent qualifying works per canonical/verified alias profile; shared works deduplicated.',
                'downloaded_at_utc_range' => source_dates.map { |m| m['retrieved_at'] }.minmax,
                'source_responses' => source_dates,
                'author_verification' => 'Reviewed name, Stanford affiliation, subject area and recent-paper consistency; same-ORCID aliases retained; uncertain aliases listed in review.',
                'limitations' => manifest['limitations'] + ['This is an importer/search smoke-test sample, not complete professor bibliographies or a representative evaluation dataset.', 'Unresolved same-name aliases are not merged.', 'Career metrics are source-reported and may contain source errors.'])
NicheRank.atomic_json(File.join(output, 'manifest.json'), manifest)
File.write(File.join(output, 'README.md'), "# Real NicheRank import sample\n\nCollected November 4, 2026 through OpenAlex public key-free lookups and official faculty sources.\n\n**Sample only:** #{professors.size} Stanford professors; at most two recent qualifying works per canonical/verified alias profile. The ten university rows supply verified institution metadata. This is not the full dataset.\n\n#{manifest['counts'].map { |name, count| "- #{name}: #{count}" }.join("\n")}\n\nAbstract coverage: #{manifest['abstract_coverage_percent']}%.\n\nConference papers are exported as `proceedings-article` to retain the agreed CSV contract; OpenAlex now calls them `conference-paper`. Journal tiers are custom team policy, not CORE conference ranks.\n\nSee manifest.json for source timestamps and limitations, review.csv for uncertainties, and db/data/manual/author_match_checks.csv in the collector workspace for identity evidence.\n\nExpected backend import command (provided by Yashwanth; not run here):\n\n```sh\nbin/rails data:import DIR=/absolute/path/to/this/sample\n```\n")
puts JSON.pretty_generate(manifest['counts'])
