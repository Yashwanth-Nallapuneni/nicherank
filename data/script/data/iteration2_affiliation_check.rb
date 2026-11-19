#!/usr/bin/env ruby
# frozen_string_literal: true

# Iteration 2 identity QA: for each added-school professor, count how many of their
# collected works list the school on that professor's own authorship (raw OpenAlex
# responses in tmp/openalex_cache retain institutions; work batches do not).
# Prints zero/low-affiliation profiles for manual review. Read-only.
require 'zlib'; require 'json'; require 'csv'; require 'set'
inst = CSV.read('db/data/manual/universities.csv', headers: true).to_h { |u| [u['name'], u['openalex_id']] }
rows = CSV.read('db/data/manual/accepted_author_matches.csv', headers: true).drop(1126)
want = rows.to_h { |r| [r['openalex_id'], r] }
stat = Hash.new { |h, k| h[k] = { 'recent' => 0, 'school' => 0, 'all' => 0, 'school_all' => 0 } }
files = `find tmp/openalex_cache -name '*.json' -newermt #{ENV.fetch('SINCE', '2026-11-15')}`.split("\n")
seen = Set.new
files.each do |f|
  j = JSON.parse(File.read(f)) rescue next
  next unless j['endpoint'] == 'works'
  Array(j.dig('response', 'results')).each do |w|
      next unless seen.add?(w['id'])
      Array(w['authorships']).each do |a|
        id = a.dig('author', 'id').to_s.split('/').last
        next unless (r = want[id])
        hit = Array(a['institutions']).any? { |i| i['id'].to_s.end_with?(inst[r['university']]) }
        s = stat[id]; s['all'] += 1; s['school_all'] += 1 if hit
        if w['publication_year'].to_i >= 2022
          s['recent'] += 1; s['school'] += 1 if hit
        end
      end
  end
end
zero = rows.select { |r| s = stat[r['openalex_id']]; s['all'] >= 5 && s['school_all'].zero? }
low = rows.select { |r| s = stat[r['openalex_id']]; s['all'] >= 5 && s['school_all'].positive? && s['school_all'] * 10 < s['all'] }
puts "new professors: #{rows.size}; with >=1 school-affiliated paper: #{rows.count { |r| stat[r['openalex_id']]['school_all'].positive? }}; no papers: #{rows.count { |r| stat[r['openalex_id']]['all'].zero? }}"
puts "ZERO school-affiliated papers (of >=5): #{zero.size}"
zero.each { |r| s = stat[r['openalex_id']]; puts "  #{r['university'][0, 18]} | #{r['name']} | #{s['all']} papers | #{r['notes'].to_s[/recent hire/] ? 'RECENT-HIRE' : r['match_confidence']}" }
puts "under 10% school-affiliated: #{low.size}"
low.each { |r| s = stat[r['openalex_id']]; a = JSON.parse(File.read("tmp/author_metadata/#{r['openalex_id']}.json"))["author"]; puts "  LOW #{r['university'][0, 16]} | #{r['name']} | #{s['school_all']}/#{s['all']} | #{Array(a['last_known_institutions']).map { |i| i['display_name'] }.first(1).join} | #{Array(a['topics']).first(1).map { |t| t['display_name'] }.join}" }
