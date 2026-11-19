# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../script/data/map_venue_rankings'

class VenueRankingMappingTest < Minitest::Test
  M = NicheRank::VenueRankingMapping

  ICORE = [
    { 'core_id' => '1', 'title' => 'International Symposium on Microarchitecture', 'acronym' => 'MICRO', 'rank' => 'A*' },
    { 'core_id' => '2', 'title' => 'International World Wide Web Conference', 'acronym' => 'WWW', 'rank' => 'A*' },
    { 'core_id' => '3', 'title' => 'Some National Conference', 'acronym' => 'SNC', 'rank' => 'National: USA' },
    { 'core_id' => '4', 'title' => 'Alpha Systems Symposium', 'acronym' => 'ASS', 'rank' => 'A' },
    { 'core_id' => '5', 'title' => 'Alpha Security Symposium', 'acronym' => 'ASS', 'rank' => 'B' }
  ].freeze
  ERA = [
    { 'core_id' => '10', 'title' => 'ACM Transactions on Graphics', 'rank' => 'A*', 'issns' => '0730-0301;1557-7368' },
    { 'core_id' => '11', 'title' => 'Unrated Journal', 'rank' => 'Not ranked', 'issns' => '1111-1111' }
  ].freeze

  def venue(type, name, papers = 10)
    { 'paper_type' => type, 'venue' => name, 'papers' => papers.to_s, 'tiered' => '0' }
  end

  def test_conference_exact_title_acronym_and_parenthesized_alias
    venues = [venue('conference-paper', 'International Symposium on Microarchitecture'), venue('conference-paper', 'MICRO'),
              venue('conference-paper', 'ACM International World Wide Web Conference (WWW)')]
    mapped, = M.conferences(venues, ICORE)
    assert_equal %w[exact_title exact_acronym parenthesized_acronym], mapped.map { |r| r['match_method'] }
    assert_equal ['A*'], mapped.map { |r| r['rank'] }.uniq
  end

  def test_workshops_findings_and_ungraded_entries_are_not_mapped
    venues = [venue('conference-paper', 'Workshop on Microarchitecture (MICRO)'), venue('conference-paper', 'Some National Conference')]
    mapped, reviews = M.conferences(venues, ICORE)
    assert_empty mapped
    assert_equal ['workshop/companion/findings/demo venue does not inherit a grade', 'CORE entry has no letter grade'], reviews.map { |r| r['reason'] }
  end

  def test_ambiguous_acronym_is_not_guessed
    mapped, reviews = M.conferences([venue('conference-paper', 'Alpha Symposium (ASS)')], ICORE)
    assert_empty mapped
    assert_equal ['ambiguous: several graded CORE entries'], reviews.map { |r| r['reason'] }
  end

  def test_journal_by_issn_title_and_ungraded
    venues = [venue('article', 'TOG'), venue('article', 'ACM Transactions on Graphics'), venue('article', 'Unrated Journal'), venue('article', 'Nothing')]
    mapped, reviews = M.journals(venues, ERA, 'TOG' => ['1557-7368'], 'ACM Transactions on Graphics' => ['0730-0301'])
    assert_equal %w[issn issn+title], mapped.map { |r| r['match_method'] }
    assert_equal ['ERA2010 journal has no letter grade'], reviews.map { |r| r['reason'] }
  end

  def test_run_writes_files
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'v.csv'), "paper_type,venue,papers,tiered\nconference-paper,MICRO,5,0\narticle,ACM Transactions on Graphics,9,0\n")
      File.write(File.join(dir, 'i.csv'), "core_id,title,acronym,rank\n1,International Symposium on Microarchitecture,MICRO,A*\n")
      File.write(File.join(dir, 'e.csv'), "core_id,title,rank,issns\n10,ACM Transactions on Graphics,A*,0730-0301\n")
      summary = M.run(File.join(dir, 'v.csv'), File.join(dir, 'i.csv'), File.join(dir, 'e.csv'), File.join(dir, 'none.json'), dir)
      assert_equal 1, summary['conference']['venues']
      assert_equal 1, summary['journal']['venues']
      assert_equal 2, NicheRank.read_csv(File.join(dir, 'venue_ranking_mappings.csv')).size
    end
  end
end
