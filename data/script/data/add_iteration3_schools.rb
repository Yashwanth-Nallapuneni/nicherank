#!/usr/bin/env ruby
# frozen_string_literal: true

# Appends iteration-3 schools to universities.csv and institution_verification.csv.
# Existing rows are never edited (the files keep their CRLF line endings) and a school
# that is already present is skipped, so re-running is safe.
# Usage: ruby script/data/add_iteration3_schools.rb schools.json
# schools.json: [{ "name", "short_name", "openalex_id", "city", "state", "cs_dept_url", "ror", "source_name" }]
require 'csv'
require 'json'

manual = File.expand_path('../../db/data/manual', __dir__)
schools = JSON.parse(File.read(ARGV.fetch(0)))

append = lambda do |file, key, headers, rows|
  path = File.join(manual, file)
  existing = CSV.read(path, headers: true, encoding: 'bom|utf-8')
  known = existing.map { |r| r[key] }
  fresh = rows.reject { |r| known.include?(r[key]) }
  next 0 if fresh.empty?
  eol = File.read(path).include?("\r\n") ? "\r\n" : "\n"
  File.open(path, 'ab') do |f|
    f.write(eol) unless File.read(path).end_with?("\n")
    fresh.each { |r| f.write(CSV.generate_line(headers.map { |h| r[h] }, row_sep: eol)) }
  end
  fresh.size
end

universities = schools.map { |s| s.slice('openalex_id', 'name', 'short_name', 'city', 'state', 'cs_dept_url') }
verification = schools.map do |s|
  { 'university' => s['name'], 'openalex_id' => s['openalex_id'], 'source_name' => s['source_name'], 'city' => s['city'],
    'ror' => "https://ror.org/#{s['ror']}", 'source_url' => "https://api.openalex.org/institutions/#{s['openalex_id']}",
    'selection_reason' => 'Matched by exact ROR ID to the main university (not a medical center or another campus); CSRankings iteration-3 school' }
end
added = append.call('universities.csv', 'name', %w[openalex_id name short_name city state cs_dept_url], universities)
verified = append.call('institution_verification.csv', 'university', %w[university openalex_id source_name city ror source_url selection_reason], verification)
puts "universities.csv: +#{added}; institution_verification.csv: +#{verified}"
