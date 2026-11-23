# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../script/data/build_homepage_fallbacks'

class HomepageFallbacksTest < Minitest::Test
  H = NicheRank::HomepageFallbacks
  SCHOOL = 'University of California Riverside'
  CSR = [{ 'name' => 'Amr Magdy Ahmed', 'affiliation' => 'Univ. of California - Riverside', 'homepage' => 'https://cs.ucr.edu/~amr' },
         { 'name' => 'Pat Lee', 'affiliation' => 'Univ. of California - Riverside', 'homepage' => 'https://a.example/pat' },
         { 'name' => 'Pat Lee', 'affiliation' => 'Univ. of California - Riverside', 'homepage' => 'https://b.example/pat' },
         { 'name' => 'Sam Kay', 'affiliation' => 'Rice University', 'homepage' => 'https://rice.example/sam' }].freeze

  def roster(*names, homepage: '')
    names.map { |n| { 'university' => SCHOOL, 'name' => n, 'homepage_url' => homepage } }
  end

  def test_fills_only_people_without_a_homepage_and_matches_name_variants
    rows = H.build(roster('Amr Magdy') + roster('Ann Has', homepage: 'https://official.example/ann'), CSR, [SCHOOL])
    assert_equal ['Amr Magdy'], rows.map { |r| r['name'] }
    assert_equal 'https://cs.ucr.edu/~amr', rows.first['homepage_url']
  end

  def test_ambiguous_or_other_school_matches_are_skipped
    assert_empty H.build(roster('Pat Lee'), CSR, [SCHOOL]) # two different homepages: never guess
    assert_empty H.build(roster('Sam Kay'), CSR, [SCHOOL]) # CSRankings lists Sam Kay at another school
  end

  def test_name_matching
    assert H.same?('Finale Doshi', 'Finale Doshi-Velez')
    assert H.same?('Bruce M. Maggs', 'Bruce MacDowell Maggs')
    refute H.same?('Alexander Ioannidis', 'Nilah Ioannidis')
  end
end
