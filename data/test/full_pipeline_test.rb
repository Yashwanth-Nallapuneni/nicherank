# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative '../script/data/lib/nicherank'
require_relative '../script/data/load_postgres'

class FullPipelineTest < Minitest::Test
  def test_full_roster_retains_professor_without_qualifying_papers
    Dir.mktmpdir do |directory|
      professor = { 'openalex_id' => 'A1', 'name' => 'Zero Papers', 'title' => 'Professor', 'university_openalex_id' => 'I1', 'match_confidence' => 'manual' }
      exporter = NicheRank::Exporter.new(universities: [{ 'openalex_id' => 'I1', 'name' => 'University' }], professors: [professor], aliases: [], works: [], keep_empty_professors: true)
      manifest = exporter.export(directory)
      assert_equal 1, manifest.dig('counts', 'professors')
      assert_equal 0, manifest.dig('counts', 'papers')
      assert_empty NicheRank::Validator.new(directory, allow_empty_professors: true).errors
      assert NicheRank.read_csv(File.join(directory, 'review.csv')).any? { |r| r['issue_type'] == 'no_papers' }
    end
  end

  def test_database_boundary_uses_confirmed_type_and_preserves_unknown_and_false
    loader = NicheRank::PostgresLoader.new(nil, 'unused')
    row = loader.transform('papers', { 'type' => 'proceedings-article', 'venue' => '', 'venue_tier' => '', 'abstract' => '', 'is_open_access' => 'false' })
    assert_equal 'conference-paper', row['paper_type']
    refute row.key?('type')
    assert_nil row['abstract']
    assert_nil row['venue_tier_source']
    assert_equal 'false', row['is_open_access']
  end
end
