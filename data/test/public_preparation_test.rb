# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../script/data/prepare_public'
require_relative '../script/data/prepare_venues'

class PublicPreparationTest < Minitest::Test
  def test_secondary_adjunct_appointment_does_not_exclude_regular_cs_professor
    status, = NicheRank::PublicPreparation.classify('Professor, Computer Science & Engineering; Adjunct Professor, Electrical and Computer Engineering')
    assert_equal 'included', status
  end

  def test_courtesy_only_cs_appointment_is_excluded
    status, = NicheRank::PublicPreparation.classify('Professor, School of Information; Professor (courtesy), EECS – Computer Science and Engineering', school: 'University of Michigan')
    assert_equal 'excluded', status
  end

  def test_teaching_emeritus_postdoc_and_adjunct_are_excluded
    ['Associate Teaching Professor', 'Professor Emerita', 'Post Doctoral Fellow', 'Adjunct Professor', 'Courtesy Faculty'].each do |title|
      status, = NicheRank::PublicPreparation.classify(title)
      assert_equal 'excluded', status, title
    end
  end

  def test_ambiguous_special_faculty_is_not_silently_approved
    status, = NicheRank::PublicPreparation.classify('Special Faculty - Contingent')
    assert_equal 'needs_review', status
  end

  def test_iteration2_classifier_applies_confirmed_scope
    {
      'Assistant Professor' => 'included',
      'Research Associate Professor of Computer Science' => 'included',
      'Department Chair; Leonard J. Shustek Professor of Computer Science; Affiliated Faculty, NYU Center for Data Science' => 'included',
      'Clinical Assistant Professor' => 'excluded',
      'Associate Professor of Instruction' => 'excluded',
      'Professor (Courtesy: Electrical and Computer Engineering)' => 'excluded',
      'Affiliate Professor; MPower Professor, Department of Linguistics' => 'excluded',
      'Professor Emeritus; Research Professor' => 'excluded',
      'In Memoriam - Distinguished Professor' => 'excluded',
      'Academic Advisor' => 'excluded',
      '' => 'needs_review'
    }.each do |title, expected|
      status, = NicheRank::PublicPreparation.classify_extended(title)
      assert_equal expected, status, title
    end
  end

  def test_core_collision_is_not_assigned_a_tier
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'source.csv')
      CSV.open(path, 'w') do |csv|
        csv << ['1', 'Conference One', 'SAME', 'CORE2023', 'A*', 'Yes', '4601', '', '']
        csv << ['2', 'Conference Two', 'SAME', 'CORE2023', 'B', 'Yes', '4602', '', '']
        csv << ['3', 'Not Ranked', 'NR', 'CORE2023', 'Unranked', 'No', '', '', '']
      end
      summary = NicheRank::VenuePreparation.prepare(path, dir)
      mappings = NicheRank.read_csv(File.join(dir, 'venue_tiers.csv'))
      refute mappings.any? { |r| r['venue'] == 'SAME' }
      refute mappings.any? { |r| r['venue'] == 'Not Ranked' }
      assert_equal 2, summary['ambiguous_mapping_rows_excluded']
      assert_equal 4, mappings.count { |r| r['kind'] == 'journal_custom' }
    end
  end

  def test_real_sample_contract_and_evidence
    root = File.expand_path('..', __dir__)
    sample = File.join(root, 'db/data/sample')
    assert_empty NicheRank::Validator.new(sample).errors
    manifest = JSON.parse(File.read(File.join(sample, 'manifest.json')))
    assert_equal false, manifest['complete_ten_school_dataset']
    assert_equal 'bounded_real_import_sample', manifest['scope']
    assert_equal 20, manifest['counts']['professors']
    assert_operator manifest['counts']['papers'], :>=, 20
    assert_equal 2, manifest['counts']['author_aliases']
    checks = NicheRank.read_csv(File.join(root, 'db/data/manual/author_match_checks.csv'))
    assert_equal 20, checks.size
    assert checks.all? { |r| !r['faculty_evidence_url'].to_s.empty? && !r['paper_titles_checked'].to_s.empty? }
  end
end
