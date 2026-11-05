#!/usr/bin/env ruby
# frozen_string_literal: true

# Raw collection is independent of identity approval. Only approved identities
# may subsequently be exported/loaded. Compressed batch files are private caches.
require 'zlib'
require_relative 'lib/nicherank'

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  NicheRank.load_openalex_key(File.join(root, '.env.local'))
  ids_file = ARGV.shift || File.join(root, 'db/data/manual/author_match_proposals.csv')
  cutoff = ENV.fetch('SNAPSHOT_CUTOFF', '2026-11-04')
  ids = NicheRank.read_csv(ids_file).map { |r| NicheRank.short_id(r.fetch('openalex_id'), 'A') }
  aliases_file = File.join(root, 'db/data/manual/accepted_author_aliases.csv')
  aliases_file = File.join(root, 'db/data/manual/author_aliases.csv') unless File.exist?(aliases_file)
  ids += NicheRank.read_csv(aliases_file).map { |r| r.fetch('alias_openalex_id') }
  ids = ids.uniq.sort
  selected = ids.to_set
  output = File.join(root, 'tmp/work_batches')
  FileUtils.mkdir_p(output)
  covered = Dir[File.join(output, '*.manifest.json')].flat_map { |f| j = JSON.parse(File.read(f)); j['cutoff'] == cutoff ? j.fetch('author_ids') : [] }.to_set
  pending = ids.reject { |id| covered.include?(id) }
  puts "#{ids.size} requested author IDs; #{pending.size} not yet collected"
  client = NicheRank::Client.new(cache: File.join(root, 'tmp/openalex_cache'), max_requests: 6000)
  queue = Queue.new
  pending.each_slice(50).with_index { |batch, index| queue << [batch, index] }
  failures = Queue.new
  fields = %w[id doi title publication_year publication_date type is_retracted cited_by_count primary_location locations primary_topic keywords open_access language abstract_inverted_index authorships]
  workers = 3.times.map do
    Thread.new do
      loop do
        begin
          batch, index = queue.pop(true)
        rescue ThreadError
          break
        end
        fingerprint = Digest::SHA256.hexdigest(JSON.generate([cutoff, batch]))
        path = File.join(output, "#{fingerprint}.jsonl.gz")
        next if File.exist?(path) && File.exist?("#{path}.manifest.json")
        count = 0
        begin
          Zlib::GzipWriter.open("#{path}.tmp") do |writer|
            client.each_page('works', 'filter' => "authorships.author.id:#{batch.join('|')},from_publication_date:2015-01-01,to_publication_date:#{cutoff},is_retracted:false,type:#{NicheRank::SOURCE_TYPES.join('|')}", 'select' => fields.join(',')) do |page|
              page.each do |work|
                work['authorships'] = Array(work['authorships']).select { |a| selected.include?(a.dig('author', 'id').to_s.split('/').last) }.map { |a| a.slice('author', 'author_position', 'is_corresponding') }
                writer.puts(JSON.generate(work))
                count += 1
              end
              puts "Batch #{index + 1}: #{count} records; #{client.requests} live requests"
              $stdout.flush
            end
          end
          File.rename("#{path}.tmp", path)
          NicheRank.atomic_json("#{path}.manifest.json", { 'author_ids' => batch, 'cutoff' => cutoff, 'records' => count, 'completed_at' => Time.now.utc.iso8601, 'sha256' => Digest::SHA256.file(path).hexdigest, 'identity_approval' => 'separate review required' })
        rescue StandardError => e
          failures << { 'batch' => index + 1, 'error' => e.message }
          break
        end
      end
    end
  end
  workers.each(&:join)
  errors = []
  errors << failures.pop until failures.empty?
  NicheRank.atomic_json(File.join(output, 'run.json'), { 'cutoff' => cutoff, 'author_ids' => ids, 'errors' => errors, 'live_requests' => client.requests, 'ended_at' => Time.now.utc.iso8601 })
  abort(JSON.generate(errors)) unless errors.empty?
end
