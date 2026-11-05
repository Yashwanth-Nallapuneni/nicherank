#!/usr/bin/env ruby
# frozen_string_literal: true
# Rebuild from the delivered CSV snapshot into an EMPTY dedicated database.
# Does not scrape, drop tables, rotate credentials or stamp Rails migrations.
require 'pg'
require 'rbconfig'
require 'open3'
require_relative 'lib/nicherank'

if $PROGRAM_NAME == __FILE__
  directory, credential, report = ARGV
  abort('Usage: rebuild_postgres.rb DATASET_DIR PRIVATE_OWNER_ENV QA_REPORT.json') unless report
  root = File.expand_path('../..', __dir__)
  directory, credential, report = [directory, credential, report].map { |p| File.expand_path(p) }
  url = File.readlines(credential, chomp: true).find { |l| l.start_with?('DATABASE_URL=') }&.split('=', 2)&.last
  db = nil
  begin
    raise 'Missing private owner DATABASE_URL' if url.to_s.empty?
    manifest = JSON.parse(File.read(File.join(directory, 'manifest.json')))
    errors = NicheRank::Validator.new(directory, allow_empty_professors: manifest['keep_empty_professors'] == true).errors
    raise errors.join('; ') unless errors.empty?
    db = PG.connect(url)
    %w[universities professors papers authorships author_aliases paper_duplicates data_review_cases dataset_metadata].each do |table|
      exists = db.exec_params('SELECT to_regclass($1)', ["public.#{table}"]).first.values.first
      raise 'Rebuild requires empty data tables; existing rows are never erased' if exists && db.exec("SELECT EXISTS(SELECT 1 FROM public.#{table})").first['exists'] == 't'
    end
    db.transaction { db.exec(File.read(File.join(root, 'db/postgres/schema.sql'))) }
    db.close
    db = nil
    [['load_postgres.rb', directory, credential], ['qa_postgres.rb', credential, directory, report]].each do |script, *args|
      out, _err, status = Open3.capture3(RbConfig.ruby, File.join(__dir__, script), *args)
      raise "#{script} failed; details suppressed" unless status.success?
      puts out
    end
    puts 'Rebuild from the delivered snapshot and full QA passed; no source API calls made.'
  rescue StandardError => e
    warn "Rebuild failed (#{e.class}); existing data was not erased. Use a private owner connection and an empty target database."
    exit 1
  ensure
    db&.close
  end
end
