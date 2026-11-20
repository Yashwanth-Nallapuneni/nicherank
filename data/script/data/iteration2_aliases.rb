#!/usr/bin/env ruby
# frozen_string_literal: true

# Iteration 2 split-profile (alias) detection for the fifteen added schools.
# Same acceptance rule as the baseline: an alternate OpenAlex profile is folded
# into the canonical professor only with the same primary ORCID, a compatible
# display name, and at least two shared coauthor names (excluding the person).
# Run after collect_work_pages.rb has collected the canonical profiles; then
# collect the accepted alias IDs with collect_work_pages.rb again.
require 'zlib'
require_relative 'lib/nicherank'
require_relative 'scan_authors'
require_relative 'lib/iteration_scope'

root = File.expand_path('../..', __dir__)
NicheRank.load_openalex_key(File.join(root, '.env.local'))
manual = File.join(root, 'db/data/manual')
scope = NicheRank::IterationScope.fetch(default: 'iteration2') # NICHE_SCOPE=iteration2_continued for the next batch
schools = scope.schools
accepted = NicheRank.read_csv(File.join(manual, 'accepted_author_matches.csv'))
known = accepted.map { |r| r['openalex_id'] }.to_set
aliases_path = File.join(manual, 'accepted_author_aliases.csv')
existing_aliases = NicheRank.read_csv(aliases_path)
known.merge(existing_aliases.map { |a| a['alias_openalex_id'] })
people = accepted.select { |r| schools.include?(r['university']) }.map do |r|
  author = JSON.parse(File.read(File.join(root, "tmp/author_metadata/#{r['openalex_id']}.json"))).fetch('author')
  r.merge('orcid' => author['orcid'].to_s.split('/').last)
end
by_orcid = people.reject { |p| p['orcid'].to_s.empty? }.group_by { |p| p['orcid'] }
client = NicheRank::Client.new(cache: File.join(root, 'tmp/openalex_cache'), max_requests: 400)

proposals = []
by_orcid.keys.sort.each_slice(50) do |batch|
  client.each_page('authors', 'filter' => "orcid:#{batch.join('|')}", 'select' => 'id,display_name,display_name_alternatives,orcid,works_count') do |authors|
    authors.each do |a|
      id = NicheRank.short_id(a['id'], 'A')
      by_orcid.fetch(a['orcid'].to_s.split('/').last, []).each do |person|
        next if known.include?(id)
        score = [a['display_name'], *Array(a['display_name_alternatives'])].map { |n| NicheRank::IdentityNames.score(person['name'], n) }.max || 0
        proposals << { 'person' => person, 'alias_id' => id, 'author' => a } if score >= 3
      end
    end
  end
end
puts "#{by_orcid.size} new professors with ORCID; #{proposals.size} same-ORCID compatible-name split candidates"

canonical_ids = proposals.map { |p| p['person']['openalex_id'] }.to_set
coauthors = Hash.new { |h, k| h[k] = Set.new }
Dir[File.join(root, 'tmp/work_batches/*.manifest.json')].each do |manifest|
  next unless (JSON.parse(File.read(manifest))['author_ids'] & canonical_ids.to_a).any?
  Zlib::GzipReader.open(manifest.delete_suffix('.manifest.json')) do |reader|
    reader.each_line do |line|
      authors = Array(JSON.parse(line)['authorships'])
      ids = authors.map { |a| a.dig('author', 'id').to_s.split('/').last }
      next unless ids.any? { |i| canonical_ids.include?(i) }
      names = authors.map { |a| NicheRank::IdentityNames.key(a.dig('author', 'display_name')) }.reject(&:empty?)
      ids.each { |i| coauthors[i].merge(names) if canonical_ids.include?(i) }
    end
  end
end

evidence_dir = File.join(root, scope.alias_dir)
FileUtils.mkdir_p(evidence_dir)
approved, evidence = [], []
proposals.each do |p|
  canonical, id, person = p['person']['openalex_id'], p['alias_id'], p['person']
  path = File.join(evidence_dir, "#{canonical}-#{id}.json")
  result = if File.exist?(path)
             JSON.parse(File.read(path))
           else
             works = client.get('works', 'filter' => "authorships.author.id:#{id},from_publication_date:2015-01-01", 'per_page' => 100,
                                'select' => 'id,title,authorships').fetch('results')
             names = works.flat_map { |w| Array(w['authorships']).map { |a| NicheRank::IdentityNames.key(a.dig('author', 'display_name')) } }.reject(&:empty?).to_set
             self_names = [person['name'], p['author']['display_name']].map { |n| NicheRank::IdentityNames.key(n) }.to_set
             shared = ((coauthors[canonical] & names) - self_names).to_a.sort
             r = { 'professor_openalex_id' => canonical, 'name' => person['name'], 'university' => person['university'], 'alias_openalex_id' => id,
                   'primary_orcid' => person['orcid'], 'alias_works_2015_plus' => works.size, 'shared_coauthor_names' => shared,
                   'approved' => shared.size >= 2,
                   'reason' => 'Same primary ORCID + compatible display name + at least two shared coauthors; otherwise withheld' }
             NicheRank.atomic_json(path, r)
             r
           end
  evidence << result
  approved << { 'professor_openalex_id' => canonical, 'alias_openalex_id' => id } if result['approved']
end
approved.uniq!
duplicates = approved.group_by { |a| a['alias_openalex_id'] }.select { |_, v| v.size > 1 }.keys
approved.reject! { |a| duplicates.include?(a['alias_openalex_id']) }
NicheRank.atomic_json(File.join(manual, scope.alias_evidence_file), evidence.sort_by { |e| [e['professor_openalex_id'], e['alias_openalex_id']] })
merged = (existing_aliases + approved).uniq { |a| a['alias_openalex_id'] }
NicheRank.write_csv(aliases_path, NicheRank::HEADERS['author_aliases'], merged)
File.binwrite(aliases_path, File.binread(aliases_path).gsub(/\r?\n/, "\r\n"))
puts "Evidence checked: #{evidence.size}; #{scope.label} aliases accepted: #{approved.size}; ambiguous withheld: #{duplicates.size}; live requests: #{client.requests}"
