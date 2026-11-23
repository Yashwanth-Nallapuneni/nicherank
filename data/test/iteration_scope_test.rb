# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../script/data/lib/nicherank'
require_relative '../script/data/lib/iteration_scope'

class IterationScopeTest < Minitest::Test
  Scope = NicheRank::IterationScope
  MANUAL = File.expand_path('../db/data/manual', __dir__)

  def test_iteration2_keeps_the_names_of_the_files_that_already_exist
    s = Scope.fetch('iteration2')
    [s.proposals_file, s.retry_file, s.review_file, s.corrections_file, s.alias_evidence_file].each do |file|
      assert File.exist?(File.join(MANUAL, file)), "#{file} must keep its audited name"
    end
    assert_equal 'tmp/iteration2/author_resolution', s.resolution_dir
    assert_equal 'tmp/iteration2/alias_verification', s.alias_dir
    assert_equal 'tmp/iteration2/retry_evidence.json', s.retry_evidence_file
    assert_equal 'iteration 2', s.label
    assert_equal 15, s.schools.size
  end

  def test_iteration2_continued_gets_its_own_files_and_never_touches_iteration2
    two, three = Scope.fetch('iteration2'), Scope.fetch('iteration2_continued')
    assert_equal 'iteration2_continued_author_match_proposals.csv', three.proposals_file
    assert_equal 'iteration 2, continued', three.label
    assert_equal 27, three.schools.size
    assert_empty two.schools & three.schools
    %i[proposals_file retry_file review_file corrections_file alias_evidence_file resolution_dir alias_dir retry_evidence_file].each do |m|
      refute_equal two.public_send(m), three.public_send(m), "#{m} must differ between batches"
    end
  end

  def test_no_scope_means_the_original_behaviour_and_unknown_scope_fails_loudly
    assert_nil Scope.fetch(nil)
    assert_nil Scope.fetch('')
    assert_equal 'iteration2', Scope.fetch(nil, default: 'iteration2').name
    assert_equal 'iteration2_continued', Scope.fetch('iteration2_continued', default: 'iteration2').name
    assert_raises(ArgumentError) { Scope.fetch('iteration9') }
  end

  def test_every_batch_school_is_in_universities_csv_and_the_roster
    universities = NicheRank.read_csv(File.join(MANUAL, 'universities.csv')).map { |u| u['name'] }
    roster = NicheRank.read_csv(File.join(MANUAL, 'faculty_raw.csv')).map { |r| r['university'] }.to_set
    Scope.names.each do |batch|
      schools = Scope.fetch(batch).schools
      assert_empty schools - universities, "#{batch}: schools missing from universities.csv"
      assert_empty schools.reject { |s| roster.include?(s) }, "#{batch}: schools without a roster"
    end
  end
end
