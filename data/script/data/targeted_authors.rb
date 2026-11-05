#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'lib/nicherank'

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  NicheRank.load_openalex_key(File.join(root, '.env.local'))
  queries = {
    'Abhi Silwal' => 'Abhisesh Silwal', 'Katie Cunningham' => 'Kathryn Cunningham',
    'Mohammod Rabbi' => 'Mashfiqui Rabbi', 'Nilou Salehi' => 'Niloufar Salehi',
    'Ben Lindquist' => 'Benjamin Lindquist', 'Alexandru Damian' => 'Alex Damian',
    'YuFeng (Kevin) Chen' => 'Yufeng Chen', 'Merrick Furst' => 'Merrick Furst',
    'Tom Costello' => 'Tom Costello', 'Michael Kim' => 'Michael P. Kim',
    'Kartik Goyal' => 'Kartik Goyal', 'Ryan Huang' => 'Ryan Huang',
    'Will Perkins' => 'William Perkins', 'Robert E Kass' => 'Robert E. Kass',
    'Steve Mussmann' => 'Steve Mussmann'
  }
  client = NicheRank::Client.new(cache: File.join(root, 'tmp/openalex_cache'), max_requests: 50)
  queries.each do |name, query|
    path = File.join(root, 'tmp/targeted_authors', Digest::SHA256.hexdigest(name) + '.json')
    next if File.exist?(path)
    result = client.get('authors', 'search' => query, 'per_page' => 100)
    NicheRank.atomic_json(path, { 'name' => name, 'query' => query, 'results' => result.fetch('results') })
    puts "#{name}: #{result.fetch('results').size} candidates"
    $stdout.flush
  end
end
