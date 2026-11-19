#!/usr/bin/env ruby
# frozen_string_literal: true

# Offline parser for the official CORE portal exports used by the
# venue_rankings table: ICORE2026 conferences and ERA2010 journals.
# It only normalizes the published lists and records provenance; it does not
# map OpenAlex venue names and never writes to the database.
require 'digest'
require 'time'
require_relative 'lib/nicherank'

module NicheRank
  module VenueRankingPreparation
    CONFERENCE_SOURCE = 'https://portal.core.edu.au/conf-ranks/?search=&by=all&source=ICORE2026&sort=atitle&page=1&do=Export'
    JOURNAL_SOURCE = 'https://portal.core.edu.au/jnl-ranks/?search=&by=all&source=ERA2010&sort=atitle&page=1&do=Export'
    ISSN = /\A\d{4}-\d{3}[\dX]\z/

    # ICORE export has no header: id,title,acronym,source,rank,has_changed,for1,for2,(blank)
    def self.conferences(input)
      rows = CSV.read(input, encoding: 'bom|utf-8')
      raise 'Unexpected ICORE2026 CSV structure' if rows.empty? || !rows.all? { |r| r.size >= 8 && r[3] == 'ICORE2026' }
      rows.map do |r|
        { 'core_id' => r[0].to_s.strip, 'title' => r[1].to_s.strip, 'acronym' => r[2].to_s.strip, 'source' => r[3],
          'rank' => r[4].to_s.strip, 'primary_for' => r[6], 'secondary_for' => r[7], 'source_url' => CONFERENCE_SOURCE }
      end
    end

    # ERA2010 journal export has a header: id,title,source,rank,has changed?,for1..3,ISSN1..4
    def self.journals(input)
      table = CSV.read(input, headers: true, encoding: 'bom|utf-8')
      required = %w[id title source rank for1 ISSN1]
      raise 'Unexpected ERA2010 journal CSV structure' unless (required - table.headers).empty? && table.all? { |r| r['source'] == 'ERA2010' }
      invalid = []
      rows = table.map do |r|
        issns = (1..4).map { |i| r["ISSN#{i}"].to_s.strip.upcase }.reject(&:empty?)
        bad, good = issns.partition { |issn| !issn.match?(ISSN) }
        invalid.concat(bad.map { |issn| { 'core_id' => r['id'], 'issn' => issn } })
        { 'core_id' => r['id'].to_s.strip, 'title' => r['title'].to_s.strip, 'source' => r['source'], 'rank' => r['rank'].to_s.strip,
          'for1' => r['for1'], 'for2' => r['for2'], 'for3' => r['for3'], 'issns' => good.uniq.join(';'), 'source_url' => JOURNAL_SOURCE }
      end
      [rows, invalid]
    end

    def self.provenance(input, url, rows)
      { 'url' => url, 'retrieved_at' => File.mtime(input).utc.iso8601, 'sha256' => Digest::SHA256.file(input).hexdigest,
        'records' => rows.size, 'letter_ranked' => rows.count { |r| TIERS.include?(r['rank']) },
        'rank_counts' => rows.group_by { |r| r['rank'] }.transform_values(&:size).sort_by { |k, v| [-v, k] }.to_h }
    end

    def self.prepare(conference_input, journal_input, directory)
      conferences = self.conferences(conference_input)
      journals, invalid_issns = self.journals(journal_input)
      NicheRank.write_csv(File.join(directory, 'icore2026.csv'), %w[core_id title acronym source rank primary_for secondary_for source_url], conferences)
      NicheRank.write_csv(File.join(directory, 'era2010_journals.csv'), %w[core_id title source rank for1 for2 for3 issns source_url], journals)
      summary = {
        'icore2026' => provenance(conference_input, CONFERENCE_SOURCE, conferences),
        'era2010_journals' => provenance(journal_input, JOURNAL_SOURCE, journals).merge(
          'journals_with_issn' => journals.count { |r| !r['issns'].empty? }, 'invalid_issns_dropped' => invalid_issns
        ),
        'notes' => [
          'Only A*/A/B/C are letter grades; other CORE labels (Unranked, National: X, Australasian X, Journal Published, Not ranked) are kept verbatim but are not grades.',
          'ERA2010 is the final CORE journal list; CORE discontinued journal rankings afterwards.',
          'These lists feed the separate venue_rankings table. papers.venue_tier (CORE2023) is unchanged.'
        ]
      }
      NicheRank.atomic_json(File.join(directory, 'venue_ranking_sources.json'), summary)
      summary
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  puts JSON.pretty_generate(NicheRank::VenueRankingPreparation.prepare(
    ARGV[0] || File.join(root, 'tmp/public_sources/icore2026_export.csv'),
    ARGV[1] || File.join(root, 'tmp/public_sources/era2010_journals_export.csv'),
    ARGV[2] || File.join(root, 'db/data/manual')
  ))
end
