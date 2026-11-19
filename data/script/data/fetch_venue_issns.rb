#!/usr/bin/env ruby
# frozen_string_literal: true

# Looks up ISSNs for journal venue names through the public OpenAlex /sources
# endpoint (read-only; no API key, no account data sent). A venue is accepted
# only when a source of type "journal" has exactly the same normalized display
# name. Results are cached so an interrupted or budget-limited run resumes.
# Usage: ruby script/data/fetch_venue_issns.rb [min_papers=3] [max_requests=3000]
require 'net/http'
require_relative 'lib/nicherank'

root = File.expand_path('..', __dir__ + '/..')
venues_path = File.join(root, 'tmp/venue_ranking/venues.csv')
cache_path = File.join(root, 'tmp/venue_ranking/source_issns.json')
min_papers = (ARGV[0] || 3).to_i
max_requests = (ARGV[1] || 3000).to_i
cache = File.exist?(cache_path) ? JSON.parse(File.read(cache_path)) : {}
todo = NicheRank.read_csv(venues_path).select { |r| r['paper_type'] == 'article' && r['papers'].to_i >= min_papers && !cache.key?(r['venue']) }
puts "#{todo.size} venues to look up (#{cache.size} cached)"

requests = 0
todo.each do |row|
  break puts('Request budget reached; rerun to resume') if requests >= max_requests
  name = row['venue']
  uri = URI('https://api.openalex.org/sources')
  uri.query = URI.encode_www_form('filter' => "display_name.search:#{name.delete(',|:')}", 'select' => 'id,display_name,issn,issn_l,type', 'per-page' => 10)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
    http.get(uri.request_uri, { 'User-Agent' => 'NicheRank-course-data/0.1', 'Accept' => 'application/json' })
  end
  requests += 1
  if response.code.to_i == 429 || response.code.to_i == 403
    puts "HTTP #{response.code}: stopping (daily free budget likely exhausted). Rerun later to resume."
    break
  end
  next puts("HTTP #{response.code} for #{name}; skipped") unless response.code == '200'
  key = NicheRank.normalize(name)
  found = JSON.parse(response.body).fetch('results', []).select { |s| s['type'] == 'journal' && NicheRank.normalize(s['display_name']) == key }
  issns = found.flat_map { |s| Array(s['issn']) + [s['issn_l']] }.compact.map(&:upcase).uniq
  cache[name] = { 'issns' => issns, 'openalex_ids' => found.map { |s| s['id'] } }
  NicheRank.atomic_json(cache_path, cache) if (requests % 50).zero?
  sleep 0.15
end
NicheRank.atomic_json(cache_path, cache)
with = cache.count { |_, v| !v['issns'].empty? }
puts "Cache now has #{cache.size} venues, #{with} with ISSNs (#{requests} requests this run)"
