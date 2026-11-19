# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../script/data/prepare_scimago_q1'
require_relative '../script/data/map_venue_rankings'

class ScimagoPreparationTest < Minitest::Test
  HEADER = "Rank;Sourceid;Title;Type;Issn;Publisher;SJR Best Quartile;Categories;Areas\n"

  def csv(dir, body)
    File.join(dir, 's.csv').tap { |path| File.write(path, HEADER + body) }
  end

  def test_keeps_only_cs_q1_and_normalizes_issn
    Dir.mktmpdir do |dir|
      input = csv(dir, <<~CSV)
        1;11;"Good CS Journal";journal;"01628828, 19393539";X;Q1;"Artificial Intelligence (Q1); Software (Q2)";Computer Science
        2;12;"Bio Journal";journal;"12345678";X;Q1;"Bioengineering (Q1); Software (Q3)";Computer Science
        3;13;"Q2 Journal";journal;"2157846X";X;Q2;"Software (Q2)";Computer Science
        4;14;"Bad ""quote" Journal;journal;"87654321";X;Q1;"Information Systems (Q1)";Computer Science
      CSV
      summary = NicheRank::ScimagoPreparation.prepare(input, dir)
      rows = NicheRank.read_csv(File.join(dir, 'scimago_cs_q1.csv'))
      assert_equal ['11', '14'], rows.map { |r| r['sourceid'] }
      assert_equal '0162-8828;1939-3539', rows.first['issns']
      assert_equal 'Artificial Intelligence', rows.first['cs_q1_categories']
      assert_equal 4, summary['journals_in_file']
    end
  end

  def test_scimago_venues_map_by_issn_and_title_only_for_q1
    list = [{ 'sourceid' => '11', 'title' => 'Good CS Journal', 'ranking' => 'Q1', 'issns' => '0162-8828' }]
    venues = [{ 'paper_type' => 'article', 'venue' => 'Good CS Journal', 'papers' => '5' },
              { 'paper_type' => 'article', 'venue' => 'Other Name', 'papers' => '3' },
              { 'paper_type' => 'conference-paper', 'venue' => 'Good CS Journal', 'papers' => '2' }]
    mapped, = NicheRank::VenueRankingMapping.scimago(venues, list, 'Other Name' => ['0162-8828'])
    assert_equal ['Good CS Journal', 'Other Name'], mapped.map { |r| r['venue'] }.sort
    assert_equal ['scimago2025'], mapped.map { |r| r['source'] }.uniq
    assert_equal ['Q1'], mapped.map { |r| r['rank'] }.uniq
  end
end
