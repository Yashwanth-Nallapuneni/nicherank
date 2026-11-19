#!/usr/bin/env ruby
# frozen_string_literal: true

# Offline mapping of OpenAlex venue names to the CORE lists saved by
# prepare_venue_rankings.rb (icore2026.csv, era2010_journals.csv).
#
# Policy (same spirit as iteration2_venue_aliases.rb):
# - only letter grades A*/A/B/C are mapped; Unranked/National/etc. never are;
# - a venue maps only when it resolves to exactly one CORE entry;
# - workshops, companion/extended-abstract/demo/poster/doctoral proceedings and
#   Findings never inherit a main-conference grade;
# - journals match by ISSN (from a cache built by fetch_venue_issns.rb) or by an
#   exact normalized title; a disagreement between the two goes to review.
# Input venues.csv columns: paper_type,venue,papers,tiered (a read-only DB snapshot).
require_relative 'lib/nicherank'

module NicheRank
  module VenueRankingMapping
    MIN_ALIAS_PAPERS = 3
    EXCLUDED = /workshop|companion|extended abstract|findings|demonstration|demo\b|poster|doctoral|adjunct|phd forum|student|tutorial|late.breaking/i
    STOP = %w[the of on and in for ieee acm international conference symposium annual proceedings sigplan sigact sigsoft sigsac sigda sigir
              spec sigmod sigkdd ieeeacm acmieee joint was previously].to_set
    MAPPING_HEADERS = %w[venue paper_type source core_id core_title rank match_method papers notes].freeze
    REVIEW_HEADERS = %w[venue paper_type papers candidate reason].freeze

    def self.words(text)
      NicheRank.normalize(text.to_s.gsub(/\([^)]*\)/, ' ')).split.reject { |w| STOP.include?(w) || w.size < 3 }.to_set
    end

    def self.graded(rows)
      rows.select { |r| TIERS.include?(r['rank']) }
    end

    def self.index_by(rows, field)
      rows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |row, index|
        key = NicheRank.normalize(row[field])
        index[key] << row unless key.empty?
      end
    end

    def self.entry(venue, source, row, method, notes)
      { 'venue' => venue['venue'], 'paper_type' => venue['paper_type'], 'source' => source, 'core_id' => row['core_id'],
        'core_title' => row['title'], 'rank' => row['rank'], 'match_method' => method, 'papers' => venue['papers'], 'notes' => notes }
    end

    def self.review(venue, candidate, reason)
      { 'venue' => venue['venue'], 'paper_type' => venue['paper_type'], 'papers' => venue['papers'], 'candidate' => candidate, 'reason' => reason }
    end

    # Returns [mapping_rows, review_rows] for conference-paper venues.
    def self.conferences(venues, icore)
      all_by_title = index_by(icore, 'title')
      all_by_acronym = index_by(icore, 'acronym')
      mapped, reviews = [], []
      venues.select { |v| v['paper_type'] == 'conference-paper' }.each do |venue|
        name = venue['venue']
        papers = venue['papers'].to_i
        if name.match?(EXCLUDED)
          reviews << review(venue, '', 'workshop/companion/findings/demo venue does not inherit a grade') if papers >= MIN_ALIAS_PAPERS && name.match?(/\([A-Za-z0-9@&\-\/ ]+\)\s*\z/)
          next
        end
        key = NicheRank.normalize(name)
        exact = all_by_title[key]
        method = 'exact_title'
        if exact.empty? && !(exact = all_by_acronym[key]).empty?
          method = 'exact_acronym'
        end
        if exact.empty? && papers >= MIN_ALIAS_PAPERS && (acronym = name[/\(([A-Za-z0-9@&\-\/ ]+)\)\s*\z/, 1])
          vw = words(name)
          exact = all_by_acronym[NicheRank.normalize(acronym)].select do |e|
            cw = words(e['title'])
            !cw.empty? && !vw.empty? && (cw & vw).size.to_f / [cw.size, vw.size].min >= 0.5
          end
          method = 'parenthesized_acronym'
        end
        next if exact.empty?
        ranked = graded(exact)
        if ranked.empty?
          reviews << review(venue, exact.map { |e| "#{e['acronym']} (#{e['rank']})" }.join(' | '), 'CORE entry has no letter grade') if papers >= 10
        elsif ranked.map { |e| e['core_id'] }.uniq.size > 1
          reviews << review(venue, ranked.map { |e| "#{e['acronym']} #{e['rank']} id#{e['core_id']}" }.join(' | '), 'ambiguous: several graded CORE entries')
        else
          row = ranked.first
          mapped << entry(venue, 'icore2026', row, method, "ICORE2026 entry #{row['core_id']} (#{row['acronym']}); #{method.tr('_', ' ')}; no workshop/findings inheritance")
        end
      end
      [mapped, reviews]
    end

    # issn_cache: { venue name => [issns] } built from OpenAlex sources.
    def self.journals(venues, era, issn_cache)
      by_issn = Hash.new { |h, k| h[k] = [] }
      era.each { |r| r['issns'].to_s.split(';').each { |i| by_issn[i] << r } }
      by_title = index_by(era, 'title')
      mapped, reviews = [], []
      venues.select { |v| v['paper_type'] == 'article' }.each do |venue|
        name = venue['venue']
        via_issn = Array(issn_cache[name]).flat_map { |i| by_issn[i] }.uniq { |r| r['core_id'] }
        via_title = by_title[NicheRank.normalize(name)]
        candidates = (via_issn + via_title).uniq { |r| r['core_id'] }
        next if candidates.empty?
        ranked = graded(candidates)
        if ranked.empty?
          reviews << review(venue, candidates.map { |c| "#{c['title']} (#{c['rank']})" }.join(' | '), 'ERA2010 journal has no letter grade') if venue['papers'].to_i >= 10
        elsif candidates.size > 1
          reviews << review(venue, ranked.map { |c| "#{c['title']} #{c['rank']} id#{c['core_id']}" }.join(' | '), 'ambiguous: ISSN and title point to different ERA2010 journals')
        else
          row = ranked.first
          method = via_issn.any? && via_title.any? ? 'issn+title' : (via_issn.any? ? 'issn' : 'exact_title')
          mapped << entry(venue, 'era2010', row, method, "ERA2010 journal #{row['core_id']}; #{method}")
        end
      end
      [mapped, reviews]
    end

    def self.run(venues_path, icore_path, era_path, issn_path, directory)
      venues = NicheRank.read_csv(venues_path)
      icore = NicheRank.read_csv(icore_path)
      era = NicheRank.read_csv(era_path)
      issn_cache = File.exist?(issn_path.to_s) ? JSON.parse(File.read(issn_path)).transform_values { |v| Array(v['issns']) } : {}
      conf_rows, conf_review = conferences(venues, icore)
      jour_rows, jour_review = journals(venues, era, issn_cache)
      sort = ->(rows) { rows.sort_by { |r| [-r['papers'].to_i, r['venue']] } }
      NicheRank.write_csv(File.join(directory, 'venue_ranking_mappings.csv'), MAPPING_HEADERS, sort.call(conf_rows + jour_rows))
      NicheRank.write_csv(File.join(directory, 'venue_ranking_review.csv'), REVIEW_HEADERS, sort.call(conf_review + jour_review))
      papers = ->(rows) { rows.sum { |r| r['papers'].to_i } }
      { 'conference' => { 'venues' => conf_rows.size, 'papers' => papers.call(conf_rows), 'review' => conf_review.size,
                          'by_method' => conf_rows.map { |r| r['match_method'] }.tally },
        'journal' => { 'venues' => jour_rows.size, 'papers' => papers.call(jour_rows), 'review' => jour_review.size,
                       'by_method' => jour_rows.map { |r| r['match_method'] }.tally, 'issn_lookups_available' => issn_cache.size } }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  manual = File.join(root, 'db/data/manual')
  puts JSON.pretty_generate(NicheRank::VenueRankingMapping.run(
    ARGV[0] || File.join(root, 'tmp/venue_ranking/venues.csv'), File.join(manual, 'icore2026.csv'),
    File.join(manual, 'era2010_journals.csv'), File.join(root, 'tmp/venue_ranking/source_issns.json'), manual
  ))
end
