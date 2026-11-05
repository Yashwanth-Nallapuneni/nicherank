#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'lib/nicherank'

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  NicheRank.load_openalex_key(File.join(root, '.env.local'))
  file = ARGV[0] || File.join(root, 'db/data/manual/author_match_proposals.csv')
  ids = NicheRank.read_csv(file).map { |r| NicheRank.short_id(r.fetch('openalex_id'), 'A') }.uniq.sort
  client = NicheRank::Client.new(cache: File.join(root, 'tmp/openalex_cache'), max_requests: 3000)
  queue, failures = Queue.new, Queue.new
  ids.each { |id| queue << id }
  3.times.map do
    Thread.new do
      loop do
        begin
          id = queue.pop(true)
        rescue ThreadError
          break
        end
        path = File.join(root, "tmp/author_metadata/#{id}.json")
        next if File.exist?(path)
        begin
          author = client.get("authors/#{id}")
          earliest = client.get('works', 'filter' => "authorships.author.id:#{id}", 'sort' => 'publication_date:asc', 'per_page' => 1, 'select' => 'id,publication_year').fetch('results').first
          NicheRank.atomic_json(path, { 'author' => author, 'first_pub_year' => earliest && earliest['publication_year'], 'retrieved_at' => Time.now.utc.iso8601 })
          puts "#{id} complete; #{client.requests} live requests"
          $stdout.flush
        rescue StandardError => e
          failures << { 'id' => id, 'error' => e.message }
          break
        end
      end
    end
  end.each(&:join)
  errors = []
  errors << failures.pop until failures.empty?
  abort(JSON.generate(errors)) unless errors.empty?
end
