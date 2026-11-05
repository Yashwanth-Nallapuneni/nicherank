#!/usr/bin/env ruby
# frozen_string_literal: true

# Account-free public-source downloader. Uses a reviewed URL registry, skips
# existing snapshots, preserves provenance, and stops at a per-run request cap.
require 'optparse'
require_relative 'lib/nicherank'

root = File.expand_path('../..', __dir__)
options = { output: File.join(root, 'tmp/public_sources'), max_requests: 200, offline: false }
OptionParser.new do |o|
  o.banner = 'ruby script/data/fetch_public.rb [--offline] [--max-requests N] [--output PATH]'
  o.on('--offline') { options[:offline] = true }
  o.on('--max-requests N', Integer) { |n| options[:max_requests] = n }
  o.on('--output PATH') { |p| options[:output] = File.expand_path(p) }
  o.on('-h', '--help') { puts o; exit }
end.parse!
sources = JSON.parse(File.read(File.join(root, 'db/data/manual/public_sources.json')))
count = 0
failures = []
FileUtils.mkdir_p(options[:output])
sources.each do |key, source|
  raise 'Invalid source key' unless key.match?(/\A[a-z0-9_\-]+\z/)
  path = File.join(options[:output], "#{key}.html")
  next if File.exist?(path)
  if options[:offline] || source['method'] == 'browser'
    failures << "#{key}: source snapshot missing#{source['method'] == 'browser' ? ' (normal browser download required)' : ''}"
    next
  end
  begin
    original = source.fetch('url')
    uri = URI(original)
    6.times do |redirect|
      raise 'Public sources must use HTTPS without credentials or API keys' unless uri.scheme == 'https' && uri.userinfo.nil? && !uri.query.to_s.match?(/api_key|token|password/i)
      raise 'Request cap reached; rerun to resume' if count >= options[:max_requests]
      sleep(0.3) unless count.zero?
      count += 1
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 45
      response = http.get(uri.request_uri, { 'User-Agent' => 'NicheRank-course-data/0.1 public faculty directory research' })
      if response.is_a?(Net::HTTPRedirection)
        raise 'Too many redirects' if redirect == 5
        uri = URI.join(uri, response.fetch('location'))
        next
      end
      raise "HTTP #{response.code}; no access-control bypass attempted" unless response.is_a?(Net::HTTPSuccess)
      body = response.body.force_encoding('UTF-8').scrub
      File.write("#{path}.tmp", body)
      File.rename("#{path}.tmp", path)
      NicheRank.atomic_json(path.sub(/\.html\z/, '.meta.json'), { 'url' => original, 'final_url' => uri.to_s, 'retrieved_at' => Time.now.utc.iso8601,
                            'status' => response.code.to_i, 'sha256' => Digest::SHA256.hexdigest(body) })
      puts "Downloaded #{key}"
      break
    end
  rescue StandardError => e
    failures << "#{key}: #{e.class}: #{e.message}"
  end
end
puts "Live public requests: #{count}; missing/failed snapshots: #{failures.size}"
failures.each { |failure| warn failure }
exit(failures.empty? ? 0 : 1)
