#!/usr/bin/env ruby
# frozen_string_literal: true
require 'open3'
require 'tmpdir'
require_relative 'lib/nicherank'

if $PROGRAM_NAME == __FILE__
  archive = File.expand_path(ARGV.fetch(0))
  bin = ENV.fetch('POSTGRES_17_BIN', '/opt/homebrew/opt/postgresql@17/bin')
  # macOS Unix socket paths have a small length limit; avoid its long TMPDIR.
  Dir.mktmpdir('nr-pg17-', '/private/tmp') do |temporary|
    data, socket = File.join(temporary, 'db'), File.join(temporary, 'socket')
    FileUtils.mkdir_p(socket, mode: 0o700)
    run = lambda do |program, *args|
      out, err, status = Open3.capture3(File.join(bin, program), *args)
      raise "#{program} failed: #{err.lines.last(3).join}" unless status.success?
      out
    end
    started = false
    begin
      run.call('initdb', '-D', data, '--no-locale', '--encoding=UTF8', '--auth-local=trust', '--auth-host=reject')
      begin
        run.call('pg_ctl', '-D', data, '-l', File.join(temporary, 'server.log'), '-o', "-h '' -k #{socket} -p 55439", '-w', 'start')
      rescue StandardError
        warn File.read(File.join(temporary, 'server.log')) if File.exist?(File.join(temporary, 'server.log'))
        raise
      end
      started = true
      run.call('createdb', '-h', socket, '-p', '55439', 'nicherank_restore_check')
      run.call('pg_restore', '-h', socket, '-p', '55439', '-d', 'nicherank_restore_check', '--no-owner', '--no-privileges', '--exit-on-error', archive)
      counts = run.call('psql', '-h', socket, '-p', '55439', '-d', 'nicherank_restore_check', '-X', '-A', '-t', '-c', "SELECT json_build_object('universities',(SELECT count(*) FROM universities),'professors',(SELECT count(*) FROM professors),'papers',(SELECT count(*) FROM papers),'authorships',(SELECT count(*) FROM authorships),'author_aliases',(SELECT count(*) FROM author_aliases));")
      manifest = JSON.parse(File.read("#{archive}.manifest.json"))
      manifest['fresh_postgres_17_restore_verified'] = true
      manifest['restored_counts'] = JSON.parse(counts)
      NicheRank.atomic_json("#{archive}.manifest.json", manifest)
      puts JSON.pretty_generate(manifest.slice('fresh_postgres_17_restore_verified', 'restored_counts', 'sha256'))
    ensure
      run.call('pg_ctl', '-D', data, '-m', 'fast', '-w', 'stop') if started
    end
  end
end
