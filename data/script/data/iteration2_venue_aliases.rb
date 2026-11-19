#!/usr/bin/env ruby
# frozen_string_literal: true

# Iteration 2 venue-tier extension (offline; no network). Adds exact OpenAlex
# conference display names of the form "... (ACRONYM)" that are aliases of a
# pinned CORE2023 conference with a letter grade, under the existing policy:
# - only CORE2023 A*/A/B/C (TBR, National, Unranked, journal-published excluded);
# - the CORE title must match the venue name (content-word overlap >= 0.5), and
#   the acronym must resolve to exactly one letter-graded CORE entry with that title;
# - workshops, companion/extended-abstract/demo/poster/doctoral proceedings and
#   Findings never inherit a main-conference grade;
# - at least 5 conference papers in the current export use the venue name.
# New journal (custom) tiers are NOT added here: they need backend-team approval.
# Usage: ruby script/data/iteration2_venue_aliases.rb [--apply]
require_relative 'lib/nicherank'

root = File.expand_path('../..', __dir__)
manual = File.join(root, 'db/data/manual')
apply = ARGV.include?('--apply')
tiers_path = File.join(manual, 'venue_tiers.csv')
tiers = NicheRank.read_csv(tiers_path)
mapped = tiers.map { |r| NicheRank.normalize(r['venue']) }.to_set
core = NicheRank.read_csv(File.join(manual, 'core2023.csv')).group_by { |r| r['acronym'].to_s.upcase }
papers = NicheRank.read_csv(File.join(root, 'data/output/full/papers.csv'))
counts = papers.select { |r| r['type'] == 'proceedings-article' && r['venue_tier'].to_s.empty? && !r['venue'].to_s.empty? }.map { |r| r['venue'] }.tally

stop = %w[the of on and in for ieee acm international conference symposium annual proceedings sigplan sigact sigsoft sigsac sigda sigir
          spec sigmod sigkdd ieeeacm acmieee joint was previously].to_set
words = ->(s) { NicheRank.normalize(s.to_s.gsub(/\([^)]*\)/, ' ')).split.reject { |w| stop.include?(w) || w.size < 3 }.to_set }
excluded = /workshop|companion|extended abstract|findings|demonstration|demo\b|poster|doctoral|adjunct|phd forum|student|tutorial|late.breaking|\bEA\)|W\)\s*\z/i

added, rejected = [], []
counts.sort_by { |v, n| [-n, v] }.each do |venue, n|
  acronym = venue[/\(([A-Za-z0-9@&\-\/ ]+)\)\s*\z/, 1]
  next unless acronym && (entries = core[acronym.upcase])
  next if mapped.include?(NicheRank.normalize(venue))
  reason = nil
  reason = 'fewer than 5 conference papers' if n < 5
  reason ||= 'workshop/companion/findings/demo venue does not inherit a grade' if venue.match?(excluded)
  vw = words.call(venue)
  matching = entries.select do |e|
    cw = words.call(e['title'])
    !cw.empty? && !vw.empty? && (cw & vw).size.to_f / [cw.size, vw.size].min >= 0.5
  end
  reason ||= "CORE2023 #{acronym} title does not match this venue (#{entries.map { |e| e['title'] }.join(' | ')})" if matching.empty?
  graded = matching.select { |e| NicheRank::TIERS.include?(e['rank']) }
  reason ||= "CORE2023 #{acronym} has no letter grade (#{matching.map { |e| e['rank'] }.uniq.join('/')})" if graded.empty?
  reason ||= "CORE2023 #{acronym} is ambiguous across #{graded.size} graded entries" if graded.map { |e| e['rank'] }.uniq.size > 1
  if reason
    rejected << { 'venue' => venue, 'papers' => n, 'acronym' => acronym, 'reason' => reason }
    next
  end
  entry = graded.first
  added << { 'venue' => venue, 'venue_tier' => entry['rank'], 'kind' => 'conference', 'source' => entry['source_url'],
             'notes' => "Iteration 2: exact OpenAlex display-name alias for CORE2023 entry #{entry['core_id']} (#{acronym}, #{entry['title']}); no workshop or findings inheritance",
             'papers' => n }
end

FileUtils.mkdir_p(File.join(root, 'reports/iteration2'))
NicheRank.write_csv(File.join(root, 'reports/iteration2/venue_added_mappings.csv'), %w[venue venue_tier papers notes], added)
NicheRank.write_csv(File.join(root, 'reports/iteration2/venue_rejected_candidates.csv'), %w[venue papers acronym reason], rejected)
puts "Added #{added.size} conference aliases covering #{added.sum { |r| r['papers'] }} papers; rejected #{rejected.size} acronym candidates"
if apply
  rows = (tiers + added.map { |r| r.except('papers') }).sort_by { |r| r['venue'] }
  NicheRank.write_csv(tiers_path, %w[venue venue_tier kind source notes], rows)
  puts "Applied to #{tiers_path}: #{rows.size} exact venue mappings"
end
