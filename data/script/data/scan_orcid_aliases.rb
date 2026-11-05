#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'lib/nicherank'
require_relative 'scan_authors'

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  NicheRank.load_openalex_key(File.join(root, '.env.local'))
  people = JSON.parse(File.read(File.join(root, 'tmp/author_resolution/decisions.json')))
  by_orcid = people.reject { |p| p.dig('author', 'orcid').to_s.empty? }.group_by { |p| p.dig('author', 'orcid').split('/').last }
  client = NicheRank::Client.new(cache: File.join(root, 'tmp/openalex_cache'), max_requests: 100)
  rows = []
  by_orcid.keys.sort.each_slice(50).with_index do |batch, index|
    client.each_page('authors', 'filter' => "orcid:#{batch.join('|')}", 'select' => 'id,display_name,display_name_alternatives,orcid,last_known_institutions,works_count,topics') do |authors|
      authors.each do |a|
        by_orcid.fetch(a['orcid'].to_s.split('/').last, []).each do |person|
          id = NicheRank.short_id(a['id'], 'A')
          next if id == person['selected_id']
          score = [a['display_name'], *Array(a['display_name_alternatives'])].map { |n| NicheRank::IdentityNames.score(person['name'], n) }.max || 0
          rows << { 'professor_openalex_id' => person['selected_id'], 'name' => person['name'], 'alias_openalex_id' => id,
                    'primary_orcid' => a['orcid'], 'compatible_name' => score >= 3, 'author' => a, 'status' => 'review_required' }
        end
      end
    end
    NicheRank.atomic_json(File.join(root, 'tmp/orcid_alias_proposals.json'), rows)
    puts "ORCID batch #{index + 1}: #{rows.size} candidate splits; #{client.requests} requests"
    $stdout.flush
  end
end
