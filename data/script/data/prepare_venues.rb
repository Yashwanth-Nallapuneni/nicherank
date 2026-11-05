#!/usr/bin/env ruby
# frozen_string_literal: true

# Offline parser for the official CORE2023 CSV export (which has no header).
# Ambiguous normalized acronyms/names are excluded, never guessed.
require_relative 'lib/nicherank'

module NicheRank
  module VenuePreparation
    SOURCE = 'https://portal.core.edu.au/conf-ranks/?search=&by=all&source=CORE2023&sort=atitle&page=1&do=Export'
    def self.prepare(input, directory)
      rows = CSV.read(input, encoding: 'bom|utf-8')
      raise 'Unexpected CORE CSV structure' unless rows.all? { |row| row.size >= 5 && row[3] == 'CORE2023' }
      full = rows.map do |r|
        { 'core_id' => r[0], 'title' => r[1].to_s.strip, 'acronym' => r[2].to_s.strip, 'source' => r[3], 'rank' => r[4],
          'primary_for' => r[6], 'secondary_for' => r[7], 'source_url' => SOURCE }
      end
      NicheRank.write_csv(File.join(directory, 'core2023.csv'), %w[core_id title acronym source rank primary_for secondary_for source_url], full)
      possible = full.select { |r| TIERS.include?(r['rank']) }.flat_map do |r|
        [r['title'], r['acronym']].reject(&:empty?).uniq.map do |venue|
          { 'venue' => venue, 'venue_tier' => r['rank'], 'kind' => 'conference', 'source' => SOURCE,
            'notes' => "CORE2023 entry #{r['core_id']}; #{venue == r['title'] ? 'exact full title' : 'exact acronym'}" }
        end
      end
      conflicts, accepted = [], []
      possible.group_by { |r| NicheRank.normalize(r['venue']) }.each_value do |group|
        if group.map { |r| r['notes'][/entry (\d+)/, 1] }.uniq.size > 1
          conflicts.concat(group)
        else
          accepted << group.first
        end
      end
      # These two journal examples were explicitly assigned A* in the teammate's
      # DATA_ANSWERS Q27. They are custom project policy, not CORE journal ranks.
      ['Journal of Machine Learning Research', 'JMLR', 'IEEE Transactions on Pattern Analysis and Machine Intelligence', 'TPAMI'].each do |name|
        accepted << { 'venue' => name, 'venue_tier' => 'A*', 'kind' => 'journal_custom', 'source' => 'Team DATA_ANSWERS.md Q27',
                      'notes' => 'Explicit team journal example; custom project tier, not a CORE conference ranking' }
      end
      accepted.sort_by! { |r| NicheRank.normalize(r['venue']) }
      NicheRank.write_csv(File.join(directory, 'venue_tiers.csv'), %w[venue venue_tier kind source notes], accepted)
      NicheRank.write_csv(File.join(directory, 'venue_mapping_conflicts.csv'), %w[venue venue_tier kind source notes], conflicts)
      summary = { 'core_records' => full.size, 'rank_counts' => full.group_by { |r| r['rank'] }.transform_values(&:size),
                  'exact_name_or_acronym_mappings' => accepted.size, 'ambiguous_mapping_rows_excluded' => conflicts.size,
                  'custom_journal_mapping_rows' => 4, 'source' => SOURCE }
      NicheRank.atomic_json(File.join(directory, 'venue_mapping_summary.json'), summary)
      summary
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  puts JSON.pretty_generate(NicheRank::VenuePreparation.prepare(ARGV[0] || File.join(root, 'tmp/public_sources/core_export.html'), ARGV[1] || File.join(root, 'db/data/manual')))
end
