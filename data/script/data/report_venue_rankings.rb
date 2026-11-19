#!/usr/bin/env ruby
# frozen_string_literal: true

# Coverage report for venue_rankings (offline). Uses the read-only venue snapshot
# (paper_type,venue,papers,tiered,tier,tiers) and db/data/manual/venue_rankings.csv.
# "Labeled" means a paper's venue has a papers.venue_tier OR a venue_rankings row.
require_relative 'lib/nicherank'

module NicheRank
  module VenueRankingReport
    def self.pct(part, whole)
      whole.zero? ? 0.0 : (100.0 * part / whole).round(1)
    end

    def self.analyze(venues, rankings)
      by_venue = rankings.group_by { |r| r['venue'] }
      kinds = { 'conference-paper' => 'conference', 'article' => 'journal' }
      out = { 'types' => {}, 'sources' => {}, 'agreement' => Hash.new(0), 'unmatched' => [] }
      venues.group_by { |v| v['paper_type'] }.each do |type, rows|
        total = rows.sum { |r| r['papers'].to_i }
        before = rows.sum { |r| r['tiered'].to_i }
        after = rows.sum { |r| by_venue.key?(r['venue']) ? r['papers'].to_i : r['tiered'].to_i }
        out['types'][kinds.fetch(type)] = { 'papers_with_venue_name' => total, 'labeled_before' => before, 'labeled_after' => after,
                                            'newly_labeled' => after - before, 'coverage_before_pct' => pct(before, total), 'coverage_after_pct' => pct(after, total) }
        rows.each do |r|
          rank = by_venue[r['venue']]
          if rank.nil?
            out['unmatched'] << r if r['tiered'].to_i < r['papers'].to_i
            next
          end
          rank.each do |m|
            s = (out['sources'][m['source']] ||= { 'venues' => 0, 'papers' => 0, 'newly_labeled' => 0, 'by_ranking' => Hash.new(0) })
            s['venues'] += 1
            s['papers'] += r['papers'].to_i
            s['newly_labeled'] += r['papers'].to_i - r['tiered'].to_i
            s['by_ranking'][m['ranking']] += r['papers'].to_i
            if m['source'] == 'icore2026' && r['tiers'].to_i == 1
              out['agreement'][r['tier'] == m['ranking'] ? 'same_grade' : "venue_tier #{r['tier']} -> ICORE2026 #{m['ranking']}"] += 1
            end
          end
        end
      end
      out['unmatched'].sort_by! { |r| -(r['papers'].to_i - r['tiered'].to_i) }
      out
    end

    def self.markdown(a, review_count, date)
      l = []
      l << "# venue_rankings coverage — #{date}"
      l << ''
      l << 'Computed offline from a read-only snapshot of the live database (conference-paper and article papers that have a venue name). Preprints and book chapters are deliberately not graded. No database was modified.'
      l << ''
      l << '| Paper type | Papers | Labeled before | Labeled after | Newly labeled | Coverage before → after |'
      l << '|---|---:|---:|---:|---:|---|'
      a['types'].each { |k, v| l << "| #{k} | #{v['papers_with_venue_name']} | #{v['labeled_before']} | #{v['labeled_after']} | +#{v['newly_labeled']} | #{v['coverage_before_pct']}% → #{v['coverage_after_pct']}% |" }
      l << ''
      l << '"Before" = papers with `papers.venue_tier` (CORE2023 or team custom). "After" adds any venue that has a `venue_rankings` row.'
      l << ''
      l << '## By source'
      l << ''
      l << '| Source | Venues | Papers | Papers with no venue_tier today | A* / A / B / C papers |'
      l << '|---|---:|---:|---:|---|'
      a['sources'].each { |k, v| l << "| #{k} | #{v['venues']} | #{v['papers']} | #{v['newly_labeled']} | #{%w[A* A B C].map { |g| v['by_ranking'][g] }.join(' / ')} |" }
      l << ''
      l << '## Agreement with the existing CORE2023 venue_tier (ICORE2026 venues)'
      l << ''
      a['agreement'].sort_by { |k, v| [k == 'same_grade' ? 0 : 1, -v] }.each { |k, v| l << "- #{k}: #{v} venues" }
      l << ''
      l << "## Still unlabeled"
      l << ''
      l << "#{a['unmatched'].size} venues have papers with no label; the biggest are in `reports/venue_rankings/unmatched_venues.csv`. Typical reasons: LNCS/series names, absent venue names, workshop/companion/Findings tracks, conferences without a letter grade, journals not on ERA2010. #{review_count} candidates are in `db/data/manual/venue_ranking_review.csv` for human review."
      l << ''
      l << 'ISSN-based journal matching is incomplete: the free OpenAlex budget covered only part of the ISSN lookups, so journals whose names differ from ERA2010 may be added later. SCImago Q1 is not included yet.'
      l.join("\n") + "\n"
    end

    def self.run(venues_path, manual, report_dir, date)
      venues = NicheRank.read_csv(venues_path)
      rankings = NicheRank.read_csv(File.join(manual, 'venue_rankings.csv'))
      analysis = analyze(venues, rankings)
      review = NicheRank.read_csv(File.join(manual, 'venue_ranking_review.csv'))
      FileUtils.mkdir_p(report_dir)
      File.write(File.join(report_dir, 'COVERAGE.md'), markdown(analysis, review.size, date))
      NicheRank.write_csv(File.join(report_dir, 'unmatched_venues.csv'), %w[paper_type venue papers unlabeled_papers],
                          analysis['unmatched'].first(500).map { |r| r.slice('paper_type', 'venue', 'papers').merge('unlabeled_papers' => r['papers'].to_i - r['tiered'].to_i) })
      analysis.except('unmatched')
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  puts JSON.pretty_generate(NicheRank::VenueRankingReport.run(ARGV[0] || File.join(root, 'tmp/venue_ranking/venues.csv'),
                                                              File.join(root, 'db/data/manual'), File.join(root, 'reports/venue_rankings'), Time.now.strftime('%Y-%m-%d')))
end
