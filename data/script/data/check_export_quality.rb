#!/usr/bin/env ruby
# frozen_string_literal: true

# Pre-load quality gate for an export directory (papers.csv, professors.csv, authorships.csv,
# universities.csv). Run it before load_postgres.rb for a new batch of schools:
#   NICHE_SCOPE=iteration3 ruby script/data/check_export_quality.rb [export_dir]
#
# BLOCKING errors (the database schema requires them, or the app cannot work without them):
#   - title, year (>= 2015), paper type, OpenAlex id on every paper; name, title, school and
#     match_confidence on every professor; unique ids; no orphan or duplicate authorships;
#     every paper linked to at least one professor; every batch school has professors and papers.
# COVERAGE errors (fields the app searches or shows: abstract, keywords, primary topic, field,
# venue, DOI, language, open-access fields, citations): the batch's papers must be filled at
# least as well as the papers of the existing schools in the SAME export, minus a tolerance.
# Existing schools' rows are only read, never changed.
require 'set'
require_relative 'lib/nicherank'
require_relative 'lib/iteration_scope'

module NicheRank
  module ExportQuality
    PAPER_TYPES = %w[article conference-paper proceedings-article preprint book-chapter].freeze
    CONFIDENCE = %w[high medium manual].freeze
    SEARCHED_FIELDS = %w[abstract keywords primary_topic field].freeze # feed the search index
    SHOWN_FIELDS = %w[venue doi language is_open_access oa_url citations].freeze
    TOLERANCE = 5.0 # percentage points below the existing schools
    MIN_SCHOOL_ABSTRACT = 60.0

    Result = Struct.new(:errors, :warnings, :stats)

    def self.blank?(value) = value.nil? || value.to_s.strip.empty?
    def self.pct(part, whole) = whole.zero? ? 100.0 : (100.0 * part / whole).round(1)

    def self.check(directory, batch_schools)
      papers = NicheRank.read_csv(File.join(directory, 'papers.csv'))
      professors = NicheRank.read_csv(File.join(directory, 'professors.csv'))
      authorships = NicheRank.read_csv(File.join(directory, 'authorships.csv'))
      universities = NicheRank.read_csv(File.join(directory, 'universities.csv'))
      errors, warnings, stats = [], [], {}

      # ---- blocking: required fields and value rules
      papers.each do |p|
        errors << "paper #{p['openalex_id']}: missing title" if blank?(p['title'])
        errors << "paper #{p['openalex_id']}: bad OpenAlex id" unless p['openalex_id'].to_s.match?(/\AW\d+\z/)
        errors << "paper #{p['openalex_id']}: year #{p['year'].inspect} must be 2015 or later" unless p['year'].to_i >= 2015
        errors << "paper #{p['openalex_id']}: unknown type #{p['type'].inspect}" unless PAPER_TYPES.include?(p['type'])
        errors << "paper #{p['openalex_id']}: negative citations" if p['citations'].to_s.match?(/\A-/)
      end
      professors.each do |p|
        %w[name title university_openalex_id].each { |f| errors << "professor #{p['openalex_id']}: missing #{f}" if blank?(p[f]) }
        errors << "professor #{p['openalex_id']}: bad match_confidence #{p['match_confidence'].inspect}" unless CONFIDENCE.include?(p['match_confidence'])
      end
      { 'paper' => papers, 'professor' => professors }.each do |label, rows|
        rows.group_by { |r| r['openalex_id'] }.each { |id, g| errors << "duplicate #{label} id #{id}" if g.size > 1 }
      end

      # ---- blocking: relationships
      paper_ids = papers.map { |p| p['openalex_id'] }.to_set
      professor_ids = professors.map { |p| p['openalex_id'] }.to_set
      pairs = Hash.new(0)
      authorships.each do |a|
        errors << "authorship: unknown professor #{a['professor_openalex_id']}" unless professor_ids.include?(a['professor_openalex_id'])
        errors << "authorship: unknown paper #{a['paper_openalex_id']}" unless paper_ids.include?(a['paper_openalex_id'])
        pairs[[a['professor_openalex_id'], a['paper_openalex_id']]] += 1
      end
      errors << "#{pairs.count { |_, n| n > 1 }} duplicate authorship pairs" if pairs.any? { |_, n| n > 1 }
      linked = authorships.map { |a| a['paper_openalex_id'] }.to_set
      orphans = paper_ids - linked
      errors << "#{orphans.size} papers have no professor (e.g. #{orphans.first(3).join(', ')})" unless orphans.empty?

      # ---- batch vs. existing schools
      school_of = universities.to_h { |u| [u['openalex_id'], u['name']] }
      prof_school = professors.to_h { |p| [p['openalex_id'], school_of[p['university_openalex_id']]] }
      batch = batch_schools.to_set
      missing = batch - school_of.values.to_set
      errors << "batch schools missing from universities.csv: #{missing.to_a.join(', ')}" unless missing.empty?
      papers_by_id = papers.to_h { |p| [p['openalex_id'], p] }
      ids_for = lambda do |in_batch|
        authorships.select { |a| batch.include?(prof_school[a['professor_openalex_id']]) == in_batch }.map { |a| a['paper_openalex_id'] }.uniq.filter_map { |id| papers_by_id[id] }
      end
      new_papers, old_papers = ids_for.call(true), ids_for.call(false)
      stats['batch_papers'] = new_papers.size
      stats['baseline_papers'] = old_papers.size
      stats['batch_professors'] = professors.count { |p| batch.include?(prof_school[p['openalex_id']]) }

      per_school = Hash.new { |h, k| h[k] = { 'professors' => 0, 'with_papers' => 0, 'papers' => Set.new } }
      professors.each { |p| s = prof_school[p['openalex_id']]; per_school[s]['professors'] += 1 if batch.include?(s) }
      authorships.each do |a|
        s = prof_school[a['professor_openalex_id']]
        next unless batch.include?(s)
        per_school[s]['papers'] << a['paper_openalex_id']
      end
      with_papers = authorships.group_by { |a| prof_school[a['professor_openalex_id']] }
      batch.each do |s|
        info = per_school[s]
        errors << "#{s}: no professors" if info['professors'].zero?
        errors << "#{s}: professors but no papers" if info['professors'].positive? && info['papers'].empty?
        n = with_papers.fetch(s, []).map { |a| a['professor_openalex_id'] }.uniq.size
        warnings << "#{s}: #{info['professors'] - n} of #{info['professors']} professors have no paper" if info['professors'].positive? && n < info['professors'] * 0.8
        abs = info['papers'].filter_map { |id| papers_by_id[id] }
        a = pct(abs.count { |p| !blank?(p['abstract']) }, abs.size)
        errors << "#{s}: only #{a}% of its papers have an abstract (minimum #{MIN_SCHOOL_ABSTRACT}%)" if abs.any? && a < MIN_SCHOOL_ABSTRACT
      end

      # ---- coverage of fields the app searches or shows, relative to the existing schools
      coverage = {}
      (SEARCHED_FIELDS + SHOWN_FIELDS).each do |field|
        # oa_url only exists for open-access papers, so it is compared among those (a school whose
        # papers are less often open access is not worse filled).
        scoped = ->(rows) { field == 'oa_url' ? rows.select { |p| p['is_open_access'].to_s == 'true' } : rows }
        new_set, old_set = scoped.call(new_papers), scoped.call(old_papers)
        new_c = pct(new_set.count { |p| !blank?(p[field]) }, new_set.size)
        old_c = pct(old_set.count { |p| !blank?(p[field]) }, old_set.size)
        coverage[field] = { 'batch' => new_c, 'existing' => old_c }
        next if old_set.empty? || new_set.empty?
        errors << "papers.#{field}: batch #{new_c}% vs existing schools #{old_c}% (more than #{TOLERANCE} points lower)" if new_c < old_c - TOLERANCE
      end
      stats['coverage'] = coverage
      prof_cov = {}
      %w[homepage_url orcid first_pub_year works_count h_index].each do |field|
        batch_p = professors.select { |p| batch.include?(prof_school[p['openalex_id']]) }
        old_p = professors.reject { |p| batch.include?(prof_school[p['openalex_id']]) }
        prof_cov[field] = { 'batch' => pct(batch_p.count { |p| !blank?(p[field]) }, batch_p.size), 'existing' => pct(old_p.count { |p| !blank?(p[field]) }, old_p.size) }
        warnings << "professors.#{field}: batch #{prof_cov[field]['batch']}% vs existing #{prof_cov[field]['existing']}%" if prof_cov[field]['batch'] < prof_cov[field]['existing'] - TOLERANCE
      end
      stats['professor_coverage'] = prof_cov
      Result.new(errors, warnings, stats)
    end

    def self.report(result)
      lines = ["Batch: #{result.stats['batch_professors']} professors, #{result.stats['batch_papers']} papers (existing schools: #{result.stats['baseline_papers']} papers)"]
      lines << 'Paper field coverage (batch vs existing schools):'
      result.stats['coverage'].each { |f, c| lines << format('  %-16s %6.1f%% vs %6.1f%%', f, c['batch'], c['existing']) }
      lines << 'Professor field coverage:'
      result.stats['professor_coverage'].each { |f, c| lines << format('  %-16s %6.1f%% vs %6.1f%%', f, c['batch'], c['existing']) }
      lines << "WARNINGS (#{result.warnings.size}):" << result.warnings.first(20).map { |w| "  - #{w}" } unless result.warnings.empty?
      lines << (result.errors.empty? ? 'RESULT: PASS - safe to load' : "RESULT: FAIL - #{result.errors.size} blocking problems") 
      lines << result.errors.first(25).map { |e| "  x #{e}" } unless result.errors.empty?
      lines.flatten.join("\n")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  scope = NicheRank::IterationScope.fetch(default: 'iteration3')
  result = NicheRank::ExportQuality.check(ARGV[0] || File.join(root, 'data/output/full'), scope.schools)
  puts NicheRank::ExportQuality.report(result)
  exit(result.errors.empty? ? 0 : 1)
end
