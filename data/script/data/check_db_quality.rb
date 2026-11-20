#!/usr/bin/env ruby
# frozen_string_literal: true

# Read-only per-school field coverage straight from the database. Run after a load to confirm that
# new schools' professors and papers are as complete as the existing ones.
# Usage: ruby script/data/check_db_quality.rb [PRIVATE_ENV_FILE]   (or set DATABASE_URL)
require 'pg'

url = ARGV[0] ? File.readlines(ARGV[0], chomp: true).find { |l| l.start_with?('DATABASE_URL=') }&.split('=', 2)&.last : ENV['DATABASE_URL']
abort('Missing DATABASE_URL (pass a private env file or set ENV)') if url.to_s.empty?
db = PG.connect(url)
db.exec('SET default_transaction_read_only = on')
filled = ->(col) { "round(100.0 * count(*) filter (where p.#{col} is not null and p.#{col}::text <> '') / nullif(count(*), 0), 0)" }
rows = db.exec(<<~SQL)
  SELECT u.name, count(DISTINCT pr.id) AS professors, count(DISTINCT p.id) AS papers,
         #{filled.call('abstract')} AS abstract, #{filled.call('keywords')} AS keywords, #{filled.call('primary_topic')} AS topic, #{filled.call('doi')} AS doi
  FROM universities u
  LEFT JOIN professors pr ON pr.university_id = u.id
  LEFT JOIN authorships a ON a.professor_id = pr.id
  LEFT JOIN papers p ON p.id = a.paper_id
  GROUP BY u.name ORDER BY u.name
SQL
puts format('%-44s %5s %7s %9s %9s %6s %5s', 'school', 'prof', 'papers', 'abstract%', 'keywords%', 'topic%', 'doi%')
bad = []
rows.each do |r|
  puts format('%-44s %5s %7s %9s %9s %6s %5s', r['name'], r['professors'], r['papers'], r['abstract'], r['keywords'], r['topic'], r['doi'])
  bad << "#{r['name']}: no papers" if r['papers'].to_i.zero?
  bad << "#{r['name']}: abstract #{r['abstract']}%" if r['papers'].to_i.positive? && r['abstract'].to_f < 60
end
t = db.exec(<<~SQL).first
  SELECT (SELECT count(*) FROM papers WHERE title IS NULL OR title = '') AS no_title,
         (SELECT count(*) FROM papers p WHERE NOT EXISTS (SELECT 1 FROM authorships a WHERE a.paper_id = p.id)) AS orphan_papers,
         (SELECT count(*) FROM professors WHERE title IS NULL OR title = '' OR name IS NULL OR name = '') AS bad_professors
SQL
puts "papers without a title: #{t['no_title']}; papers without a professor: #{t['orphan_papers']}; professors without name/title: #{t['bad_professors']}"
bad << 'papers without a title' unless t['no_title'].to_i.zero?
bad << 'papers without a professor' unless t['orphan_papers'].to_i.zero?
puts bad.empty? ? 'DB CHECK: PASS' : "DB CHECK: REVIEW\n  #{bad.first(15).join("\n  ")}"
