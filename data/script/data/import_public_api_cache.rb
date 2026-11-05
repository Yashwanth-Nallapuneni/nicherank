#!/usr/bin/env ruby
# frozen_string_literal: true

# Reuse reviewed public API downloads when the keyed collector starts. These are
# source caches only; importing them does not approve faculty/author identities.
require_relative 'lib/nicherank'
root = File.expand_path('../..', __dir__)
directory = File.join(root, 'tmp/public_sources')
cache = File.join(root, 'tmp/openalex_cache')
count = 0
Dir[File.join(directory, '*.meta.json')].sort.each do |path|
  metadata = JSON.parse(File.read(path))
  uri = URI(metadata.fetch('url'))
  next unless uri.host == 'api.openalex.org'
  endpoint = uri.path.sub(%r{\A/}, '')
  next unless endpoint.match?(%r{\A(?:institutions|authors|works)(?:/[IAW]\d+)?\z})
  params = URI.decode_www_form(uri.query.to_s).to_h.sort.to_h
  raise 'Credential-bearing public source URL rejected' if params.key?('api_key')
  response = JSON.parse(File.read(path.sub(/\.meta\.json\z/, '.html')))
  next if response['error']
  fingerprint = Digest::SHA256.hexdigest(JSON.generate([endpoint, params]))
  target = File.join(cache, "#{fingerprint}.json")
  next if File.exist?(target)
  NicheRank.atomic_json(target, { 'endpoint' => endpoint, 'params' => params, 'retrieved_at' => metadata['retrieved_at'], 'response' => response })
  count += 1
end
puts "Imported #{count} public API responses into the key-free local cache; no network requests."
