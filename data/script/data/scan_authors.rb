#!/usr/bin/env ruby
# frozen_string_literal: true

# Cheap first pass: scan institutional CS author pools with list queries, then
# match roster names locally. Unmatched/ambiguous records still need searches.
require_relative 'lib/nicherank'

module NicheRank
  module IdentityNames
    def self.tokens(name)
      name.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z0-9\s-]/, ' ').tr('-', ' ').split
    end

    def self.key(name)
      tokens(name).join
    end

    def self.score(roster_name, candidate_name)
      left, right = tokens(roster_name), tokens(candidate_name)
      return 0 if left.empty? || right.empty?
      return 4 if left.join == right.join
      return 3 if left.first == right.first && left.last == right.last
      return 2 if left.last == right.last && left.first[0] == right.first[0] && [left.first.size, right.first.size].min == 1
      0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  NicheRank.load_openalex_key(File.join(root, '.env.local'))
  manual = File.join(root, 'db/data/manual')
  progress_dir = File.join(root, 'tmp/author_scan')
  schools = NicheRank.read_csv(File.join(manual, 'universities.csv'))
  roster = NicheRank.read_csv(File.join(manual, 'faculty_raw.csv'))
  client = NicheRank::Client.new(cache: File.join(root, 'tmp/openalex_cache'), max_requests: Integer(ENV.fetch('NICHE_REQUEST_CAP', '2000')))
  fields = 'id,display_name,display_name_alternatives,orcid,last_known_institutions,works_count,summary_stats,topics,counts_by_year'
  schools.each do |school|
    people = roster.select { |p| p['university'] == school['name'] }
    targets = people.group_by { |p| NicheRank::IdentityNames.tokens(p['name']).last }
    found, scanned, pages = {}, 0, 0
    path = File.join(progress_dir, "#{school['openalex_id']}.json")
    if File.exist?(path) && JSON.parse(File.read(path))['complete']
      puts "#{school['short_name']}: complete cached institutional scan"
      next
    end
    filter = "last_known_institutions.id:#{school['openalex_id']},topics.field.id:17,works_count:>9"
    begin
      client.each_page('authors', 'filter' => filter, 'select' => fields, 'sort' => 'works_count:desc') do |authors|
        authors.each do |author|
          variants = [author['display_name'], *Array(author['display_name_alternatives'])].compact
          possibilities = variants.flat_map { |name| targets.fetch(NicheRank::IdentityNames.tokens(name).last, []) }.uniq
          possibilities.each do |person|
            score = variants.map { |name| NicheRank::IdentityNames.score(person['name'], name) }.max
            next if score < 2
            found[person['name']] ||= {}
            found[person['name']][NicheRank.short_id(author['id'], 'A')] = { 'name_score' => score, 'author' => author }
          end
        end
        scanned += authors.size
        pages += 1
        NicheRank.atomic_json(path, { 'university' => school['name'], 'institution_id' => school['openalex_id'], 'complete' => false,
                                     'profiles_scanned' => scanned, 'pages' => pages, 'candidates' => found, 'roster_count' => people.size })
        $stdout.puts "#{school['short_name']}: #{scanned} profiles scanned; #{found.size}/#{people.size} roster names with candidates; #{client.requests} new requests" if pages % 10 == 0
        $stdout.flush
      end
      state = JSON.parse(File.read(path))
      state['complete'] = true
      NicheRank.atomic_json(path, state)
      puts "#{school['short_name']}: finished; #{found.size}/#{people.size} names with candidate profiles"
    rescue StandardError => e
      warn "Scan stopped safely: #{e.class}: #{e.message}"
      exit 1
    end
  end
  puts "Institutional scans complete. These are candidates, not automatically verified identities. Live requests: #{client.requests}."
end
