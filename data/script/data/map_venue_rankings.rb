#!/usr/bin/env ruby
# frozen_string_literal: true

# Offline mapping of OpenAlex venue names to the CORE lists saved by
# prepare_venue_rankings.rb (icore2026.csv, era2010_journals.csv).
#
# Policy (same spirit as iteration2_venue_aliases.rb):
# - only letter grades A*/A/B/C are mapped; Unranked/National/etc. never are;
# - a venue maps only by an exact title/acronym or a reviewed alias to one CORE entry;
# - workshops, companion/extended-abstract/demo/poster/doctoral proceedings and
#   Findings never inherit a main-conference grade;
# - journals match by ISSN (from a cache built by fetch_venue_issns.rb) or by an
#   exact normalized title; a disagreement between the two goes to review.
# Use --conferences-only to preserve the existing journal mappings without an ISSN cache.
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

    # Reuse reviewed names, never old grades. IDs must still identify the same
    # conference in both editions; changed identities require a new review.
    def self.legacy_aliases(legacy, previous, icore)
      old = previous.to_h { |r| [r['core_id'], r] }
      current = icore.to_h { |r| [r['core_id'], r] }
      legacy.filter_map do |alias_row|
        next unless alias_row['kind'] == 'conference'
        id = alias_row['notes'].to_s[/CORE2023 entry (\d+)/, 1]
        next unless old[id] && current[id]
        next unless %w[title acronym].all? { |field| NicheRank.normalize(old[id][field]) == NicheRank.normalize(current[id][field]) }

        { 'venue' => alias_row['venue'], 'core_id' => id }
      end
    end

    # Venue identity is independent of OpenAlex's article/conference-paper label.
    # Combine counts but retain the canonical publication kind in the output.
    def self.conferences(venues, icore, aliases: [])
      all_by_title = index_by(icore, 'title')
      all_by_acronym = index_by(icore, 'acronym')
      by_id = icore.to_h { |r| [r['core_id'], r] }
      by_alias = index_by(aliases, 'venue').transform_values do |rows|
        rows.map { |r| by_id.fetch(r['core_id']) }.uniq
      end
      mapped, reviews = [], []
      published = venues.select { |v| %w[conference-paper article].include?(v['paper_type']) }
      published.group_by { |v| v['venue'] }.each do |name, records|
        venue = { 'venue' => name, 'paper_type' => 'conference-paper', 'papers' => records.sum { |v| v['papers'].to_i }.to_s }
        papers = venue['papers'].to_i
        key = NicheRank.normalize(name)
        exact = all_by_title[key]
        method = 'exact_title'
        if exact.empty? && !(exact = all_by_acronym[key]).empty?
          method = 'exact_acronym'
        end
        # Exact reviewed names can also identify independently ranked workshops.
        reviewed = by_alias.fetch(key, [])
        if reviewed.any?
          method = 'reviewed_alias' if exact.empty?
          exact = (exact + reviewed).uniq { |e| e['core_id'] }
        end
        if exact.empty? && name.match?(EXCLUDED)
          reviews << review(venue, '', 'workshop/companion/findings/demo venue does not inherit a grade') if papers >= MIN_ALIAS_PAPERS && name.match?(/\([A-Za-z0-9@&\-\/ ]+\)\s*\z/)
          next
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
        # Even an ungraded alternative makes identity ambiguous.
        if exact.map { |e| e['core_id'] }.uniq.size > 1
          reviews << review(venue, exact.map { |e| "#{e['acronym']} #{e['rank']} id#{e['core_id']}" }.join(' | '), 'ambiguous: several CORE entries')
        elsif graded(exact).empty?
          reviews << review(venue, exact.map { |e| "#{e['acronym']} (#{e['rank']})" }.join(' | '), 'CORE entry has no letter grade') if papers >= 10
        elsif method == 'parenthesized_acronym'
          reviews << review(venue, exact.first['core_id'], 'non-exact name requires a reviewed alias; acronym and word overlap alone are insufficient')
        else
          row = exact.first
          mapped << entry(venue, 'icore2026', row, method, "ICORE2026 entry #{row['core_id']} (#{row['acronym']}); #{method.tr('_', ' ')}; no workshop/findings inheritance")
        end
      end
      [mapped, reviews]
    end

    LETTER = ->(row) { TIERS.include?(row['rank']) }
    Q1_ONLY = ->(row) { row['rank'] == 'Q1' }

    # Matches journal venues against one list. issn_cache: { venue name => [issns] }.
    # list rows need core_id, title, rank and issns ("a;b"). Grades are filtered by `gradable`.
    def self.match_journals(venues, list, source, gradable, issn_cache, ungraded_reason)
      by_issn = Hash.new { |h, k| h[k] = [] }
      list.each { |r| r['issns'].to_s.split(';').each { |i| by_issn[i] << r } }
      by_title = index_by(list, 'title')
      mapped, reviews = [], []
      venues.select { |v| v['paper_type'] == 'article' }.each do |venue|
        name = venue['venue']
        via_issn = Array(issn_cache[name]).flat_map { |i| by_issn[i] }.uniq { |r| r['core_id'] }
        via_title = by_title[NicheRank.normalize(name)]
        candidates = (via_issn + via_title).uniq { |r| r['core_id'] }
        next if candidates.empty?
        ranked = candidates.select(&gradable)
        if ranked.empty?
          reviews << review(venue, candidates.map { |c| "#{c['title']} (#{c['rank']})" }.join(' | '), ungraded_reason) if venue['papers'].to_i >= 10
        elsif candidates.size > 1
          reviews << review(venue, ranked.map { |c| "#{c['title']} #{c['rank']} id#{c['core_id']}" }.join(' | '), "ambiguous: ISSN and title point to different #{source} journals")
        else
          row = ranked.first
          method = via_issn.any? && via_title.any? ? 'issn+title' : (via_issn.any? ? 'issn' : 'exact_title')
          mapped << entry(venue, source, row, method, "#{source} journal #{row['core_id']}; #{method}")
        end
      end
      [mapped, reviews]
    end

    def self.journals(venues, era, issn_cache)
      match_journals(venues, era, 'era2010', LETTER, issn_cache, 'ERA2010 journal has no letter grade')
    end

    def self.scimago(venues, q1_rows, issn_cache)
      list = q1_rows.map { |r| { 'core_id' => r['sourceid'], 'title' => r['title'], 'rank' => r['ranking'], 'issns' => r['issns'] } }
      match_journals(venues, list, 'scimago2025', Q1_ONLY, issn_cache, 'SCImago journal is not Q1')
    end

    def self.run(venues_path, icore_path, era_path, issn_path, directory, scimago_path = nil, conferences_only: false)
      venues = NicheRank.read_csv(venues_path)
      icore = NicheRank.read_csv(icore_path)
      era = NicheRank.read_csv(era_path)
      issn_cache = File.exist?(issn_path.to_s) ? JSON.parse(File.read(issn_path)).transform_values { |v| Array(v['issns']) } : {}
      legacy_path = File.join(directory, 'venue_tiers.csv')
      previous_path = File.join(directory, 'core2023.csv')
      aliases = File.exist?(legacy_path) && File.exist?(previous_path) ? legacy_aliases(NicheRank.read_csv(legacy_path), NicheRank.read_csv(previous_path), icore) : []
      aliases_path = File.join(directory, 'icore2026_aliases.csv')
      aliases += NicheRank.read_csv(aliases_path) if File.exist?(aliases_path)
      conf_rows, conf_review = conferences(venues, icore, aliases: aliases)
      if conferences_only
        # Preserve ISSN-reviewed journal mappings when refreshing only CORE.
        existing = NicheRank.read_csv(File.join(directory, 'venue_ranking_mappings.csv'))
        jour_rows = existing.select { |r| r['source'] == 'era2010' }
        q1_rows = existing.select { |r| r['source'] == 'scimago2025' }
        jour_review = NicheRank.read_csv(File.join(directory, 'venue_ranking_review.csv')).select { |r| r['paper_type'] == 'article' }
        q1_review = []
      else
        jour_rows, jour_review = journals(venues, era, issn_cache)
        q1_rows, q1_review = scimago_path && File.exist?(scimago_path) ? scimago(venues, NicheRank.read_csv(scimago_path), issn_cache) : [[], []]
      end
      # A bare shared title cannot override an identified journal (e.g. IDA).
      journal_names = (jour_rows + q1_rows).map { |r| r['venue'] }.to_set
      conf_rows.reject! do |row|
        next false unless journal_names.include?(row['venue'])

        conf_review << review(row, row['core_id'], 'name also identifies a journal; conference identity needs review')
        true
      end
      sort = ->(rows) { rows.sort_by { |r| [-r['papers'].to_i, r['venue']] } }
      NicheRank.write_csv(File.join(directory, 'venue_ranking_mappings.csv'), MAPPING_HEADERS, sort.call(conf_rows + jour_rows + q1_rows))
      NicheRank.write_csv(File.join(directory, 'venue_ranking_review.csv'), REVIEW_HEADERS, sort.call(conf_review + jour_review + q1_review))
      papers = ->(rows) { rows.sum { |r| r['papers'].to_i } }
      { 'conference' => { 'venues' => conf_rows.size, 'papers' => papers.call(conf_rows), 'review' => conf_review.size,
                          'by_method' => conf_rows.map { |r| r['match_method'] }.tally },
        'journal' => { 'venues' => jour_rows.size, 'papers' => papers.call(jour_rows), 'review' => jour_review.size,
                       'by_method' => jour_rows.map { |r| r['match_method'] }.tally, 'issn_lookups_available' => issn_cache.size },
        'scimago_q1' => { 'venues' => q1_rows.size, 'papers' => papers.call(q1_rows), 'review' => q1_review.size, 'by_method' => q1_rows.map { |r| r['match_method'] }.tally } }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  conferences_only = !!ARGV.delete('--conferences-only')
  root = File.expand_path('../..', __dir__)
  manual = File.join(root, 'db/data/manual')
  puts JSON.pretty_generate(NicheRank::VenueRankingMapping.run(
    ARGV[0] || File.join(root, 'tmp/venue_ranking/venues.csv'), File.join(manual, 'icore2026.csv'),
    File.join(manual, 'era2010_journals.csv'), File.join(root, 'tmp/venue_ranking/source_issns.json'), manual,
    File.join(manual, 'scimago_cs_q1.csv'), conferences_only: conferences_only
  ))
end
