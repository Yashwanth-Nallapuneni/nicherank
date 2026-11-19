# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'pg'
require_relative '../script/data/load_venue_rankings'

# Runs against a throw-away local Postgres cluster; skipped when the server binaries are missing.
class VenueRankingLoaderTest < Minitest::Test
  BIN = Dir['/opt/homebrew/opt/postgresql@*/bin'].max.to_s

  def setup
    skip 'local postgres binaries not found' unless File.exist?(File.join(BIN, 'initdb'))
    @dir = Dir.mktmpdir('vr_pg')
    @port = 55_000 + rand(900)
    system(File.join(BIN, 'initdb'), '-D', File.join(@dir, 'data'), '-A', 'trust', '-U', 'tester', out: File::NULL, err: File::NULL) || skip('initdb failed')
    system(File.join(BIN, 'pg_ctl'), '-D', File.join(@dir, 'data'), '-o', "-p #{@port} -k #{@dir}", '-l', File.join(@dir, 'log'), '-w', 'start', out: File::NULL) || skip('server did not start')
    @db = PG.connect(host: @dir, port: @port, user: 'tester', dbname: 'postgres')
    @db.exec("CREATE TABLE papers (id serial PRIMARY KEY, venue text)")
    @db.exec("INSERT INTO papers (venue) VALUES ('Conf A'), ('Conf A'), ('Jnl'), ('Other')")
    @manual = File.join(@dir, 'manual')
    FileUtils.mkdir_p(@manual)
    @schema = File.expand_path('../db/postgres/venue_rankings.sql', __dir__)
  end

  def teardown
    @db&.close
    system(File.join(BIN, 'pg_ctl'), '-D', File.join(@dir, 'data'), '-m', 'immediate', 'stop', out: File::NULL, err: File::NULL) if @dir
    FileUtils.rm_rf(@dir) if @dir
  end

  def write(rows)
    NicheRank.write_csv(File.join(@manual, 'venue_rankings.csv'), %w[venue kind source source_id ranking match_method notes], rows)
  end

  def row(venue, source, ranking)
    { 'venue' => venue, 'kind' => 'conference', 'source' => source, 'source_id' => '1', 'ranking' => ranking, 'match_method' => 'exact_title', 'notes' => 'a, "b"' }
  end

  def loader
    NicheRank::VenueRankingLoader.new(@db, @manual, @schema)
  end

  def count
    @db.exec('SELECT count(*) AS n FROM venue_rankings').first['n'].to_i
  end

  def test_dry_run_rolls_back_everything_including_the_table
    write([row('Conf A', 'icore2026', 'A*')])
    report = loader.run
    assert_equal false, report['applied']
    assert_equal 1, report['rows_after']
    assert_nil @db.exec("SELECT to_regclass('public.venue_rankings') AS t").first['t']
  end

  def test_apply_is_idempotent_syncs_and_joins_papers
    write([row('Conf A', 'icore2026', 'A*'), row('Conf A', 'scimago2025', 'Q1'), row('Jnl', 'era2010', 'B')])
    first = loader.run(apply: true)
    assert_equal true, first['applied']
    assert_equal({ 'papers' => 3, 'venues' => 2 }, first['papers_joined'])
    second = loader.run(apply: true)
    assert_equal 3, second['rows_after']
    assert_equal 0, second['removed']
    write([row('Conf A', 'icore2026', 'A')])
    third = loader.run(apply: true)
    assert_equal 2, third['removed']
    assert_equal 1, count
    assert_equal 'A', @db.exec("SELECT ranking FROM venue_rankings").first['ranking']
    assert_equal 'a, "b"', @db.exec("SELECT notes FROM venue_rankings").first['notes']
  end

  def test_refuses_without_papers_table_and_unmanaged_sources
    write([row('Conf A', 'other', 'A')])
    assert_raises(RuntimeError) { loader.run(apply: true) }
    write([row('Conf A', 'icore2026', 'A')])
    @db.exec('DROP TABLE papers')
    assert_raises(RuntimeError) { loader.run(apply: true) }
  end
end
