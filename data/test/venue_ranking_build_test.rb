# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../script/data/build_venue_rankings'

class VenueRankingBuildTest < Minitest::Test
  B = NicheRank::VenueRankingBuild
  LISTS = { 'icore2026' => { '1' => { 'rank' => 'A*' } }, 'era2010' => { '10' => { 'rank' => 'B' } } }.freeze

  def mapping(venue, type, source, id, rank)
    { 'venue' => venue, 'paper_type' => type, 'source' => source, 'core_id' => id, 'rank' => rank, 'match_method' => 'exact_title', 'notes' => '' }
  end

  def test_builds_sorted_rows_with_kind
    rows = B.build([mapping('J', 'article', 'era2010', '10', 'B'), mapping('C', 'conference-paper', 'icore2026', '1', 'A*')], LISTS)
    assert_equal %w[J C], rows.map { |r| r['venue'] }
    assert_equal %w[journal conference], rows.map { |r| r['kind'] }
  end

  def test_rejects_duplicates_wrong_rank_and_unknown_ids
    assert_raises(RuntimeError) { B.build([mapping('C', 'conference-paper', 'icore2026', '1', 'A*')] * 2, LISTS) }
    assert_raises(RuntimeError) { B.build([mapping('C', 'conference-paper', 'icore2026', '1', 'A')], LISTS) }
    assert_raises(RuntimeError) { B.build([mapping('C', 'conference-paper', 'icore2026', '99', 'A*')], LISTS) }
    assert_raises(RuntimeError) { B.build([mapping('C', 'conference-paper', 'icore2026', '1', 'National')], LISTS) }
  end

  def test_rejects_venue_that_is_both_conference_and_journal
    rows = [mapping('X', 'article', 'era2010', '10', 'B'), mapping('X', 'conference-paper', 'icore2026', '1', 'A*')]
    assert_raises(RuntimeError) { B.build(rows, LISTS) }
  end
end
