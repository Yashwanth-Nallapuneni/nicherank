# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../script/data/prepare_public'
require_relative '../script/data/lib/iteration3_rosters'

class Iteration3RostersTest < Minitest::Test
  UVA = <<~HTML
    <ul><li class="people_list_row"><h2 class="people_list_item_name"><a href="/faculty/a-one"><span>Ann One﻿</span></a></h2>
      <span class="people_list_item_title">Associate Professor, Computer Science</span></li>
    <li class="people_list_row"><h2 class="people_list_item_name"><a href="/faculty/b-two"><span>Bo Two</span></a></h2>
      <span class="people_list_item_title">Associate Professor, Electrical and Computer Engineering</span>
      <span class="people_list_item_title">Associate Professor, Computer Science (by Courtesy)</span></li>
    <li class="people_list_row"><h2 class="people_list_item_name"><a href="/faculty/c-three"><span>Cy Three</span></a></h2>
      <span class="people_list_item_title">Thomas Professor</span><span class="people_list_item_title">Computer Science, Data Science</span></li></ul>
  HTML

  UTAH = <<~HTML
    <div class="t-inside"><div class="t-entry"><h2>Reg Ular</h2><h4>Assistant Professor</h4><a href="https://x.edu/~r">Website</a></div></div>
    <h2>Adjunct Faculty</h2>
    <div class="t-inside"><div class="t-entry"><h2>Ad Junct</h2></div></div>
  HTML

  def prepare(dir, key, html)
    File.write(File.join(dir, "#{key}.html"), html)
    File.write(File.join(dir, "#{key}.meta.json"), JSON.generate('url' => "https://example.edu/#{key}"))
    prep = NicheRank::PublicPreparation.new(source_dir: dir, manual: dir)
    prep.send(key)
    prep.candidates.map { |r| r.merge('status' => r['eligibility_status'] || NicheRank::PublicPreparation.classify_extended(r['title']).first) }
  end

  def test_uva_strips_invisible_characters_and_excludes_courtesy_only_faculty
    Dir.mktmpdir do |dir|
      rows = prepare(dir, 'uva_cs', UVA).to_h { |r| [r['name'], r] }
      assert_equal ['Ann One', 'Bo Two', 'Cy Three'], rows.keys
      assert_equal 'included', rows['Ann One']['status']
      assert_equal 'excluded', rows['Bo Two']['status']
      assert_equal 'included', rows['Cy Three']['status'] # rank and department are separate entries
    end
  end

  def test_utah_keeps_the_adjunct_section_as_excluded_evidence
    Dir.mktmpdir do |dir|
      rows = prepare(dir, 'utah_faculty', UTAH).to_h { |r| [r['name'], r] }
      assert_equal 'included', rows['Reg Ular']['status']
      assert_equal 'https://x.edu/~r', rows['Reg Ular']['homepage_url']
      assert_equal 'excluded', rows['Ad Junct']['status']
      assert_match(/Adjunct Faculty/, rows['Ad Junct']['eligibility_reason'])
    end
  end

  def test_merge_replaces_only_iteration3_schools_and_is_repeatable
    require_relative '../script/data/prepare_iteration3'
    existing = [{ 'university' => 'Stanford University', 'name' => 'Old Prof' }, { 'university' => 'Duke University', 'name' => 'Stale Row' }]
    fresh = [{ 'university' => 'Duke University', 'name' => 'New Row' }]
    once = NicheRank::Iteration3.merge(existing, fresh, NicheRank::PublicPreparation::ITERATION3_SCHOOLS)
    assert_equal ['New Row', 'Old Prof'], once.map { |r| r['name'] }
    assert_equal once, NicheRank::Iteration3.merge(once, fresh, NicheRank::PublicPreparation::ITERATION3_SCHOOLS)
  end

  def test_iteration3_schools_do_not_overlap_the_existing_ones
    # The first 25 rows are the original ten schools plus iteration 2; iteration-3 schools are appended after them.
    existing = NicheRank.read_csv(File.expand_path('../db/data/manual/universities.csv', __dir__)).first(25).map { |u| u['name'] }
    assert_equal 25, existing.size
    assert_empty existing & NicheRank::PublicPreparation::ITERATION3_SCHOOLS
    assert_equal 27, NicheRank::PublicPreparation::ITERATION3_SCHOOLS.uniq.size
  end
end
