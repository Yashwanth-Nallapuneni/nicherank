# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../script/data/check_export_quality'

class ExportQualityTest < Minitest::Test
  Q = NicheRank::ExportQuality
  OLD = 'Old University'
  NEW = 'New University'

  def paper(id, **over)
    { 'openalex_id' => "W#{id}", 'title' => "Paper #{id}", 'abstract' => 'An abstract.', 'year' => '2022', 'type' => 'article', 'venue' => 'Journal X',
      'venue_tier' => '', 'citations' => '3', 'doi' => "10.1/#{id}", 'primary_topic' => 'Topic', 'field' => 'Computer Science', 'keywords' => 'a; b',
      'is_open_access' => 'true', 'oa_url' => 'https://x.example/p', 'language' => 'en' }.merge(over)
  end

  def professor(id, school_id, **over)
    { 'openalex_id' => "A#{id}", 'name' => "Prof #{id}", 'university_openalex_id' => school_id, 'title' => 'Professor', 'homepage_url' => 'https://h.example',
      'orcid' => '0000', 'first_pub_year' => '2005', 'works_count' => '50', 'h_index' => '10', 'match_confidence' => 'high' }.merge(over)
  end

  # one existing and one batch professor, each with 20 papers
  def good_export
    papers, authorships = [], []
    { 1 => 'I1', 2 => 'I2' }.each do |p, _|
      20.times do |i|
        id = p * 100 + i
        papers << paper(id)
        authorships << { 'professor_openalex_id' => "A#{p}", 'paper_openalex_id' => "W#{id}", 'position' => 'first', 'is_corresponding' => 'false' }
      end
    end
    { papers: papers, professors: [professor(1, 'I1'), professor(2, 'I2')], authorships: authorships,
      universities: [{ 'openalex_id' => 'I1', 'name' => OLD }, { 'openalex_id' => 'I2', 'name' => NEW }] }
  end

  def run_check(data)
    Dir.mktmpdir do |dir|
      data.each do |name, rows|
        headers = rows.flat_map(&:keys).uniq
        NicheRank.write_csv(File.join(dir, "#{name}.csv"), headers, rows)
      end
      Q.check(dir, [NEW])
    end
  end

  def test_a_complete_batch_passes
    result = run_check(good_export)
    assert_empty result.errors
    assert_equal 20, result.stats['batch_papers']
    assert_equal 100.0, result.stats['coverage']['abstract']['batch']
  end

  def test_missing_title_year_or_type_blocks_the_load
    data = good_export
    data[:papers][25] = paper(125, 'title' => '')
    data[:papers][26] = paper(126, 'year' => '2014')
    data[:papers][27] = paper(127, 'type' => 'podcast')
    errors = run_check(data).errors
    assert(errors.any? { _1.include?('missing title') })
    assert(errors.any? { _1.include?('must be 2015 or later') })
    assert(errors.any? { _1.include?('unknown type') })
  end

  def test_batch_abstract_coverage_far_below_existing_schools_blocks_the_load
    data = good_export
    data[:papers].each { |p| p['abstract'] = '' if p['openalex_id'].delete('W').to_i >= 200 && p['openalex_id'].delete('W').to_i.odd? } # half of the batch has none
    errors = run_check(data).errors
    assert(errors.any? { _1.start_with?('papers.abstract:') }, errors.inspect)
    assert(errors.any? { _1.include?('only 50.0% of its papers have an abstract') }, errors.inspect)
  end

  def test_each_searched_and_shown_field_is_compared_with_existing_schools
    data = good_export
    data[:papers].each { |p| p['keywords'] = '' if p['openalex_id'].delete('W').to_i >= 200 }
    assert(run_check(data).errors.any? { _1.start_with?('papers.keywords:') })
  end

  def test_papers_without_a_professor_and_broken_references_block_the_load
    data = good_export
    data[:papers] << paper(999)
    data[:authorships] << { 'professor_openalex_id' => 'A404', 'paper_openalex_id' => 'W100', 'position' => 'last', 'is_corresponding' => 'false' }
    errors = run_check(data).errors
    assert(errors.any? { _1.include?('papers have no professor') })
    assert(errors.any? { _1.include?('unknown professor A404') })
  end

  def test_a_batch_school_with_professors_but_no_papers_blocks_the_load
    data = good_export
    data[:authorships].reject! { |a| a['professor_openalex_id'] == 'A2' }
    data[:papers].reject! { |p| p['openalex_id'].delete('W').to_i >= 200 }
    assert(run_check(data).errors.any? { _1 == "#{NEW}: professors but no papers" })
  end

  def test_professor_required_fields_and_confidence
    data = good_export
    data[:professors][1] = professor(2, 'I2', 'title' => '', 'match_confidence' => 'guess')
    errors = run_check(data).errors
    assert(errors.any? { _1.include?('missing title') })
    assert(errors.any? { _1.include?('bad match_confidence') })
  end

  def test_oa_url_is_compared_among_open_access_papers_only
    data = good_export
    # the batch has fewer open-access papers, but every open-access paper has its link
    data[:papers].each { |p| p.merge!('is_open_access' => 'false', 'oa_url' => '') if p['openalex_id'].delete('W').to_i >= 200 && p['openalex_id'].delete('W').to_i.odd? }
    assert_empty run_check(data).errors
    # open-access papers without a link are still caught
    data[:papers].each { |p| p['oa_url'] = '' if p['openalex_id'].delete('W').to_i >= 200 && p['is_open_access'] == 'true' }
    assert(run_check(data).errors.any? { _1.start_with?('papers.oa_url:') })
  end

  def test_report_says_pass_or_fail
    assert_match(/RESULT: PASS/, Q.report(run_check(good_export)))
    bad = good_export
    bad[:papers][0] = paper(100, 'title' => '')
    assert_match(/RESULT: FAIL/, Q.report(run_check(bad)))
  end
end
