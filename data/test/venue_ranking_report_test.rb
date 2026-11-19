# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../script/data/report_venue_rankings'

class VenueRankingReportTest < Minitest::Test
  def test_counts_new_labels_and_grade_changes
    venues = [{ 'paper_type' => 'conference-paper', 'venue' => 'Conf A', 'papers' => '10', 'tiered' => '10', 'tier' => 'A', 'tiers' => '1' },
              { 'paper_type' => 'conference-paper', 'venue' => 'Conf B', 'papers' => '4', 'tiered' => '0', 'tier' => '', 'tiers' => '0' },
              { 'paper_type' => 'article', 'venue' => 'Jnl', 'papers' => '5', 'tiered' => '0', 'tier' => '', 'tiers' => '0' },
              { 'paper_type' => 'article', 'venue' => 'Unknown', 'papers' => '7', 'tiered' => '0', 'tier' => '', 'tiers' => '0' }]
    rankings = [{ 'venue' => 'Conf A', 'source' => 'icore2026', 'ranking' => 'A*' }, { 'venue' => 'Conf B', 'source' => 'icore2026', 'ranking' => 'B' },
                { 'venue' => 'Jnl', 'source' => 'era2010', 'ranking' => 'A' }]
    a = NicheRank::VenueRankingReport.analyze(venues, rankings)
    assert_equal 4, a['types']['conference']['newly_labeled']
    assert_equal 5, a['types']['journal']['newly_labeled']
    assert_equal 1, a['agreement']['venue_tier A -> ICORE2026 A*']
    assert_equal ['Unknown'], a['unmatched'].map { |r| r['venue'] }
    assert_match(/Newly labeled/, NicheRank::VenueRankingReport.markdown(a, 0, '2026-01-01'))
  end
end
