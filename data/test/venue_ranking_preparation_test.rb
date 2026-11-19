# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../script/data/prepare_venue_rankings'

class VenueRankingPreparationTest < Minitest::Test
  def write(dir, name, text)
    File.join(dir, name).tap { |path| File.write(path, text) }
  end

  def fixtures(dir)
    conf = write(dir, 'conf.csv', <<~CSV)
      1, International Symposium on Microarchitecture ,MICRO,ICORE2026,A,No,4606,,
      2,"Conference on Things, Stuff",CTS,ICORE2026,National: USA,Yes,46,4612,
      3,Some Workshop,SW,ICORE2026,C,No,4612,,
    CSV
    jnl = write(dir, 'jnl.csv', <<~CSV)
      id,title,source,rank,has changed?,for1,for2,for3,ISSN1,ISSN2,ISSN3,ISSN4
      10,IEEE Transactions on Pattern Analysis and Machine Intelligence,ERA2010,A*,No,0801,,,0162-8828,1939-3539,,
      11,Journal Without ISSN,ERA2010,Not ranked,No,0806,,,,,,
      12,Odd Journal,ERA2010,C,No,0803,,,1234-567x,BAD,,
    CSV
    [conf, jnl]
  end

  def test_normalizes_both_lists_and_records_provenance
    Dir.mktmpdir do |dir|
      conf, jnl = fixtures(dir)
      summary = NicheRank::VenueRankingPreparation.prepare(conf, jnl, dir)

      conferences = NicheRank.read_csv(File.join(dir, 'icore2026.csv'))
      assert_equal 'International Symposium on Microarchitecture', conferences.first['title']
      assert_equal 'Conference on Things, Stuff', conferences[1]['title']
      assert_equal 'National: USA', conferences[1]['rank']
      assert_equal 2, summary['icore2026']['letter_ranked']

      journals = NicheRank.read_csv(File.join(dir, 'era2010_journals.csv'))
      assert_equal '0162-8828;1939-3539', journals.first['issns']
      assert_equal '', journals[1]['issns'].to_s
      assert_equal '1234-567X', journals[2]['issns']
      assert_equal [{ 'core_id' => '12', 'issn' => 'BAD' }], summary['era2010_journals']['invalid_issns_dropped']
      assert_equal 2, summary['era2010_journals']['journals_with_issn']
      assert_match(/\A\h{64}\z/, summary['icore2026']['sha256'])
      assert File.exist?(File.join(dir, 'venue_ranking_sources.json'))
    end
  end

  def test_rejects_wrong_edition
    Dir.mktmpdir do |dir|
      _, jnl = fixtures(dir)
      conf = write(dir, 'old.csv', "1,Old Conf,OC,CORE2023,A,No,46,,\n")
      assert_raises(RuntimeError) { NicheRank::VenueRankingPreparation.prepare(conf, jnl, dir) }
    end
  end
end
