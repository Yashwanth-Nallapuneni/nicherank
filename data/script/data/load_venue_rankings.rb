#!/usr/bin/env ruby
# frozen_string_literal: true

# Loads db/data/manual/venue_rankings.csv into the additive venue_rankings table.
# - Creates the table from db/postgres/venue_rankings.sql if it is missing.
# - Syncs the managed sources (icore2026, era2010, scimago2025): upsert on
#   (venue, source), delete rows of those sources that are no longer in the CSV.
# - Never touches papers or any other table.
# - DRY RUN by default (everything is rolled back). Pass --apply to commit.
# Usage: ruby script/data/load_venue_rankings.rb [--apply] [PRIVATE_ENV_FILE]
#        (without a file it uses ENV['DATABASE_URL'])
require 'pg'
require_relative 'lib/nicherank'

module NicheRank
  class VenueRankingLoader
    MANAGED_SOURCES = %w[icore2026 era2010 scimago2025].freeze
    COLUMNS = %w[venue kind source source_id ranking match_method notes].freeze

    def initialize(db, manual, schema_sql)
      @db, @manual, @schema_sql = db, manual, schema_sql
    end

    def run(apply: false)
      rows = NicheRank.read_csv(File.join(@manual, 'venue_rankings.csv'))
      raise 'venue_rankings.csv is empty' if rows.empty?
      bad = rows.reject { |r| MANAGED_SOURCES.include?(r['source']) }
      raise "Unmanaged sources in CSV: #{bad.map { |r| r['source'] }.uniq.join(', ')}" unless bad.empty?
      report = nil
      @db.transaction do |conn|
        raise 'papers table not found; refusing to run' unless conn.exec("SELECT to_regclass('public.papers') AS t").first['t']
        conn.exec(File.read(@schema_sql))
        before = conn.exec('SELECT count(*) AS n FROM venue_rankings').first['n'].to_i
        conn.exec('CREATE TEMP TABLE venue_rankings_stage ON COMMIT DROP AS SELECT venue, kind, source, source_id, ranking, match_method, notes FROM venue_rankings WITH NO DATA')
        conn.exec('ALTER TABLE venue_rankings_stage ALTER COLUMN source_id DROP NOT NULL')
        conn.copy_data("COPY venue_rankings_stage (#{COLUMNS.join(', ')}) FROM STDIN WITH (FORMAT csv)") do
          rows.each { |r| conn.put_copy_data(CSV.generate_line(COLUMNS.map { |c| r[c] })) }
        end
        upserted = conn.exec(<<~SQL).cmd_tuples
          INSERT INTO venue_rankings (#{COLUMNS.join(', ')})
          SELECT #{COLUMNS.join(', ')} FROM venue_rankings_stage
          ON CONFLICT (venue, source) DO UPDATE SET kind = EXCLUDED.kind, source_id = EXCLUDED.source_id,
            ranking = EXCLUDED.ranking, match_method = EXCLUDED.match_method, notes = EXCLUDED.notes
        SQL
        removed = conn.exec_params(<<~SQL, ["{#{MANAGED_SOURCES.join(',')}}"]).cmd_tuples
          DELETE FROM venue_rankings v WHERE v.source = ANY($1::text[])
            AND NOT EXISTS (SELECT 1 FROM venue_rankings_stage s WHERE s.venue = v.venue AND s.source = v.source)
        SQL
        report = { 'csv_rows' => rows.size, 'rows_before' => before, 'upserted' => upserted, 'removed' => removed,
                   'rows_after' => conn.exec('SELECT count(*) AS n FROM venue_rankings').first['n'].to_i,
                   'by_source' => conn.exec('SELECT source, count(*) AS n FROM venue_rankings GROUP BY 1 ORDER BY 1').to_h { |r| [r['source'], r['n'].to_i] },
                   'papers_joined' => conn.exec(<<~SQL).first.transform_values(&:to_i) }
          SELECT count(DISTINCT p.id) AS papers, count(DISTINCT v.venue) AS venues
          FROM papers p JOIN venue_rankings v ON v.venue = p.venue
        SQL
        raise DryRun unless apply
      end
    rescue DryRun
      report.merge('applied' => false)
    else
      report.merge('applied' => true)
    end

    class DryRun < StandardError; end
  end
end

if $PROGRAM_NAME == __FILE__
  apply = ARGV.delete('--apply')
  file = ARGV.first
  url = file ? File.readlines(file, chomp: true).find { |l| l.start_with?('DATABASE_URL=') }&.split('=', 2)&.last : ENV['DATABASE_URL']
  abort('Missing DATABASE_URL (pass a private env file or set ENV)') if url.to_s.empty?
  root = File.expand_path('../..', __dir__)
  db = PG.connect(url)
  puts JSON.pretty_generate(NicheRank::VenueRankingLoader.new(db, File.join(root, 'db/data/manual'), File.join(root, 'db/postgres/venue_rankings.sql')).run(apply: !apply.nil?))
end
