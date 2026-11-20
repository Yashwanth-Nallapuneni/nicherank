#!/usr/bin/env ruby
# frozen_string_literal: true

# Some official directories give no profile link (e.g. UC Riverside's "View Profile" button has no
# address). For eligible iteration-3 faculty without a homepage_url this looks the person up in
# CSRankings' public faculty list (https://github.com/emeryberger/CSrankings, csrankings.csv) and
# writes db/data/manual/iteration3_homepage_fallbacks.csv. prepare_iteration3.rb applies that file
# only where the official directory gave no link. Names are matched on the same school with
# compatible surname and first name; ambiguous matches are skipped.
# Usage: ruby script/data/build_homepage_fallbacks.rb [path/to/csrankings.csv]
require 'csv'
require 'digest'
require_relative 'lib/nicherank'
require_relative 'lib/iteration_scope'

module NicheRank
  module HomepageFallbacks
    # our school name => the spelling CSRankings uses
    AFFILIATION = {
      'Northwestern University' => 'Northwestern University', 'University of California Riverside' => 'Univ. of California - Riverside',
      'University of Virginia' => 'University of Virginia', 'Rutgers University' => 'Rutgers University', 'University of Utah' => 'University of Utah',
      'Duke University' => 'Duke University', 'Pennsylvania State University' => 'Pennsylvania State University', 'Texas A&M University' => 'Texas A&M University',
      'University of California Santa Barbara' => 'Univ. of California - Santa Barbara', 'Boston University' => 'Boston University',
      'George Mason University' => 'George Mason University', 'University of California Santa Cruz' => 'Univ. of California - Santa Cruz',
      'Harvard University' => 'Harvard University', 'Yale University' => 'Yale University', 'Arizona State University' => 'Arizona State University',
      'Johns Hopkins University' => 'Johns Hopkins University', 'University of Illinois Chicago' => 'University of Illinois at Chicago',
      'Virginia Tech' => 'Virginia Tech', 'North Carolina State University' => 'North Carolina State University',
      'University of North Carolina at Chapel Hill' => 'University of North Carolina', 'Ohio State University' => 'Ohio State University',
      'Rice University' => 'Rice University', 'University of Colorado Boulder' => 'University of Colorado Boulder', 'Brown University' => 'Brown University',
      'University of California Davis' => 'Univ. of California - Davis', 'University at Buffalo' => 'University at Buffalo',
      'University of Minnesota' => 'University of Minnesota'
    }.freeze

    def self.tokens(name)
      name.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase.gsub(/\([^)]*\)/, ' ').gsub(/[^a-z\s'-]/, ' ').tr("'-", ' ').split.reject { |t| %w[jr sr ii iii iv].include?(t) }
    end

    # "Finale Doshi" ~ "Finale Doshi-Velez", "Bruce M. Maggs" ~ "Bruce MacDowell Maggs"
    def self.same?(a, b)
      ta, tb = tokens(a), tokens(b)
      return false if ta.empty? || tb.empty?
      first = ta.first == tb.first || (ta.first[0] == tb.first[0] && [ta.first.size, tb.first.size].min == 1)
      first && ((ta.last(2) & tb.last(2)).any? || (tb.include?(ta.last) && ta.include?(tb.last)))
    end

    def self.build(roster, csrankings, schools)
      by_school = csrankings.group_by { |r| r['affiliation'] }
      roster.filter_map do |person|
        next unless schools.include?(person['university']) && person['homepage_url'].to_s.strip.empty?
        pool = (by_school[AFFILIATION[person['university']]] || []).select { |c| !c['homepage'].to_s.strip.empty? && same?(person['name'], c['name']) }
        homepages = pool.map { |c| c['homepage'].strip }.uniq
        next unless homepages.size == 1 # ambiguous or unknown: leave blank rather than guess
        { 'university' => person['university'], 'name' => person['name'], 'homepage_url' => homepages.first, 'source' => 'CSRankings csrankings.csv (public faculty list)' }
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  manual = File.join(root, 'db/data/manual')
  path = ARGV[0] || File.join(root, 'tmp/iteration3/gap/csrankings.csv')
  abort "CSRankings file not found: #{path}" unless File.exist?(path)
  roster = NicheRank.read_csv(File.join(manual, 'faculty_raw.csv'))
  rows = NicheRank::HomepageFallbacks.build(roster, NicheRank.read_csv(path), NicheRank::IterationScope.fetch('iteration3').schools)
  NicheRank.write_csv(File.join(manual, 'iteration3_homepage_fallbacks.csv'), %w[university name homepage_url source], rows)
  puts "fallback homepages: #{rows.size}; csrankings.csv sha256 #{Digest::SHA256.file(path).hexdigest[0, 16]}"
end
