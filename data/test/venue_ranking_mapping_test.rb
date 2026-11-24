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
    mapped, = M.conferences(venues, ICORE, aliases: [{ 'venue' => venues.last['venue'], 'core_id' => '2' }])
    assert_equal %w[exact_title exact_acronym reviewed_alias], mapped.map { |r| r['match_method'] }
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
    assert_equal ['ambiguous: several CORE entries'], reviews.map { |r| r['reason'] }
  end

  def test_reviewed_aliases_use_current_grades_and_require_stable_identity
    previous = ICORE.map(&:dup)
    previous.first['rank'] = 'C'
    legacy = [
      { 'venue' => 'Microarchitecture proceedings', 'kind' => 'conference', 'notes' => 'CORE2023 entry 1' },
      { 'venue' => 'Not a conference', 'kind' => 'journal_custom', 'notes' => 'CORE2023 entry 1' },
      { 'venue' => 'Retired entry', 'kind' => 'conference', 'notes' => 'CORE2023 entry 99' }
    ]
    aliases = M.legacy_aliases(legacy, previous, ICORE)
    assert_equal ['Microarchitecture proceedings'], aliases.map { |r| r['venue'] }
    mapped, = M.conferences([venue('article', 'Microarchitecture proceedings', 1),
                            venue('conference-paper', 'Microarchitecture proceedings', 2)], ICORE, aliases: aliases)
    assert_equal [['A*', '3', 'conference-paper']], mapped.map { |r| r.values_at('rank', 'papers', 'paper_type') }
    previous.first['title'] = 'A different conference'
    assert_empty M.legacy_aliases(legacy, previous, ICORE)
  end

  def test_independently_ranked_workshops_and_ambiguous_or_ungraded_aliases
    workshop = { 'core_id' => '6', 'title' => 'Workshop on Widgets', 'acronym' => 'WOW', 'rank' => 'B' }
    aliases = [{ 'venue' => 'Ambiguous', 'core_id' => '1' }, { 'venue' => 'Ambiguous', 'core_id' => '3' },
               { 'venue' => 'National alias', 'core_id' => '3' }]
    venues = ['Workshop on Widgets', 'Workshop on Widgets Companion (WOW)', 'Ambiguous', 'National alias', 'Other Symposium on Microarchitecture (MICRO)']
    mapped, reviews = M.conferences(venues.map { |name| venue('conference-paper', name) }, ICORE + [workshop], aliases: aliases)
    assert_equal ['Workshop on Widgets'], mapped.map { |r| r['venue'] }
    assert_equal 4, reviews.size
    assert_includes reviews.map { |r| r['reason'] }, 'ambiguous: several CORE entries'
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

  def test_conference_refresh_preserves_issn_mappings_and_defers_shared_journal_names
    Dir.mktmpdir do |dir|
      paths = %w[v.csv i.csv e.csv none.json].map { |file| File.join(dir, file) }
      File.write(paths[0], "paper_type,venue,papers,tiered\narticle,Shared name,5,0\nconference-paper,MICRO,9,0\n")
      File.write(paths[1], "core_id,title,acronym,rank\n1,International Symposium on Microarchitecture,MICRO,A*\n2,Shared name,SN,A\n")
      File.write(paths[2], "core_id,title,rank,issns\n10,Journal full title,B,0730-0301\n")
      journal = { 'venue' => 'Shared name', 'paper_type' => 'article', 'source' => 'era2010', 'core_id' => '10',
                  'core_title' => 'Journal full title', 'rank' => 'B', 'match_method' => 'issn', 'papers' => '5', 'notes' => 'Reviewed ISSN' }
      NicheRank.write_csv(File.join(dir, 'venue_ranking_mappings.csv'), M::MAPPING_HEADERS, [journal])
      NicheRank.write_csv(File.join(dir, 'venue_ranking_review.csv'), M::REVIEW_HEADERS, [])
      2.times do
        M.run(*paths, dir, conferences_only: true)
        rows = NicheRank.read_csv(File.join(dir, 'venue_ranking_mappings.csv'))
        assert_equal [journal], rows.select { |r| r['source'] == 'era2010' }
        assert_equal ['MICRO'], rows.select { |r| r['source'] == 'icore2026' }.map { |r| r['venue'] }
        assert_equal ['name also identifies a journal; conference identity needs review'],
                     NicheRank.read_csv(File.join(dir, 'venue_ranking_review.csv')).map { |r| r['reason'] }
      end
    end
  end
end
