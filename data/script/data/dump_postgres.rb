#!/usr/bin/env ruby
# frozen_string_literal: true
require 'open3'
require_relative 'lib/nicherank'

if $PROGRAM_NAME == __FILE__
  credential_file, output = ARGV
  abort('Usage: dump_postgres.rb PRIVATE_ENV OUTPUT.dump') unless output
  line = File.readlines(credential_file, chomp: true).find { |l| l.start_with?('DATABASE_URL=') }
  uri = URI(line.split('=', 2).last)
  query = URI.decode_www_form(uri.query.to_s).to_h
  env = { 'PGHOST' => uri.host, 'PGPORT' => (uri.port || 5432).to_s, 'PGUSER' => URI.decode_www_form_component(uri.user),
          'PGPASSWORD' => URI.decode_www_form_component(uri.password), 'PGDATABASE' => uri.path.delete_prefix('/'),
          'PGSSLMODE' => query.fetch('sslmode', 'require'), 'PGCONNECT_TIMEOUT' => '20' }
  env['PGCHANNELBINDING'] = query['channel_binding'] if query['channel_binding']
  bin = ENV.fetch('POSTGRES_17_BIN', '/opt/homebrew/opt/postgresql@17/bin')
  version, _, status = Open3.capture3(File.join(bin, 'pg_dump'), '--version')
  abort('Postgres 17 pg_dump is required') unless status.success? && version.match?(/\b17\./)
  FileUtils.mkdir_p(File.dirname(File.expand_path(output)))
  _, _, status = Open3.capture3(env, File.join(bin, 'pg_dump'), '--format=custom', '--no-owner', '--no-privileges', '--file', "#{output}.tmp")
  abort('Database dump failed; connection details suppressed') unless status.success?
  _, _, status = Open3.capture3(File.join(bin, 'pg_restore'), '--list', "#{output}.tmp")
  abort('Dump archive verification failed') unless status.success?
  File.rename("#{output}.tmp", output)
  NicheRank.atomic_json("#{output}.manifest.json", { 'created_at' => Time.now.utc.iso8601, 'pg_dump_version' => version.strip,
    'sha256' => Digest::SHA256.file(output).hexdigest, 'bytes' => File.size(output), 'archive_list_verified' => true, 'contains_roles_or_passwords' => false })
  puts "Verified Postgres 17 archive: #{File.basename(output)} (#{File.size(output)} bytes)"
end
