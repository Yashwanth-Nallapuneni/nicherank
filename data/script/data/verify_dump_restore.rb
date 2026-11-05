#!/usr/bin/env ruby
# frozen_string_literal: true
require 'open3'
require 'tmpdir'
require 'rbconfig'
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
      counts = run.call('psql', '-h', socket, '-p', '55439', '-d', 'nicherank_restore_check', '-X', '-A', '-t', '-c', "SELECT json_build_object('universities',(SELECT count(*) FROM universities),'professors',(SELECT count(*) FROM professors),'papers',(SELECT count(*) FROM papers),'authorships',(SELECT count(*) FROM authorships),'author_aliases',(SELECT count(*) FROM author_aliases),'paper_duplicates',(SELECT count(*) FROM paper_duplicates),'data_review_cases',(SELECT count(*) FROM data_review_cases));")
      if ARGV[1]
        dataset = File.expand_path(ARGV[1])
        credential = File.join(temporary, 'local.env')
        File.write(credential, "DATABASE_URL=postgresql:///nicherank_restore_check?host=#{URI.encode_www_form_component(socket)}&port=55439\n")
        File.chmod(0o600, credential)
        outputs = []
        2.times do
          out, err, status = Open3.capture3(RbConfig.ruby, File.join(__dir__, 'load_postgres.rb'), dataset, credential, '--reconcile')
          raise "Local audited reconciliation failed: #{err}" unless status.success?
          outputs << out
        end
        # A second load must not rewrite any unchanged entity/link rows.
        raise 'Repeated load is not idempotent' unless outputs.last.lines.grep(/inserted\/changed/).all? { |line| line.include?('; 0 inserted/changed') }
        report = File.join(temporary, 'qa.json')
        _, err, status = Open3.capture3(RbConfig.ruby, File.join(__dir__, 'qa_postgres.rb'), credential, dataset, report)
        raise "Local reconciled database QA failed: #{err}" unless status.success?
        qa = JSON.parse(File.read(report))
        root = File.expand_path('../..', __dir__)
        NicheRank.atomic_json(File.join(root, 'reports/audit/local_reconciliation_test.json'), { 'passed' => true, 'checked_at' => Time.now.utc.iso8601,
          'baseline_counts' => JSON.parse(counts), 'audited_counts' => qa['counts'], 'second_load_changed_zero_rows' => true, 'checks' => qa['checks'] })
        puts 'Local v1-to-v2 reconciliation, repeat-load idempotency and QA passed.'
      end
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
