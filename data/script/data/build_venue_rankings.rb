#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds the final venue_rankings rows from the reviewed mappings written by
# map_venue_rankings.rb and checks them against the saved CORE lists. Offline:
# no database access. The table definition is db/postgres/venue_rankings.sql.
require_relative 'lib/nicherank'

module NicheRank
  module VenueRankingBuild
    HEADERS = %w[venue kind source source_id ranking match_method notes].freeze
    KIND = { 'conference-paper' => 'conference', 'article' => 'journal' }.freeze
    LISTS = { 'icore2026' => 'icore2026.csv', 'era2010' => 'era2010_journals.csv' }.freeze

    def self.build(mappings, lists)
      rows = mappings.map do |m|
        kind = KIND.fetch(m['paper_type']) { raise "Unknown paper_type #{m['paper_type'].inspect} for #{m['venue']}" }
        { 'venue' => m['venue'], 'kind' => kind, 'source' => m['source'], 'source_id' => m['core_id'], 'ranking' => m['rank'],
          'match_method' => m['match_method'], 'notes' => m['notes'] }
      end
      errors = validate(rows, lists)
      raise "venue_rankings validation failed:\n#{errors.first(20).join("\n")}" unless errors.empty?
      rows.sort_by { |r| [r['source'], r['venue']] }
    end

    def self.validate(rows, lists)
      errors = []
      rows.group_by { |r| [r['venue'], r['source']] }.each { |k, v| errors << "duplicate #{k.inspect}" if v.size > 1 }
      rows.each do |r|
        errors << "blank venue" if r['venue'].to_s.strip.empty?
        errors << "#{r['venue']}: ranking #{r['ranking'].inspect} is not A*/A/B/C" unless TIERS.include?(r['ranking'])
        entry = lists.fetch(r['source'], {})[r['source_id']]
        if entry.nil? then errors << "#{r['venue']}: #{r['source']} id #{r['source_id']} not in saved list"
        elsif entry['rank'] != r['ranking'] then errors << "#{r['venue']}: ranking #{r['ranking']} differs from list rank #{entry['rank']}"
        end
      end
      conflicts = rows.group_by { |r| r['venue'] }.select { |_, v| v.map { |r| r['kind'] }.uniq.size > 1 }
      conflicts.each_key { |venue| errors << "#{venue}: appears as both conference and journal" }
      errors
    end

    def self.run(manual)
      lists = LISTS.transform_values { |file| NicheRank.read_csv(File.join(manual, file)).to_h { |r| [r['core_id'], r] } }
      rows = build(NicheRank.read_csv(File.join(manual, 'venue_ranking_mappings.csv')), lists)
      NicheRank.write_csv(File.join(manual, 'venue_rankings.csv'), HEADERS, rows)
      { 'rows' => rows.size, 'by_source' => rows.group_by { |r| r['source'] }.transform_values(&:size),
        'by_ranking' => rows.group_by { |r| r['ranking'] }.transform_values(&:size).sort.to_h }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts JSON.pretty_generate(NicheRank::VenueRankingBuild.run(ARGV[0] || File.expand_path('../../db/data/manual', __dir__)))
end
