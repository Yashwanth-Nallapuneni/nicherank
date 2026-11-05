#!/usr/bin/env ruby
# frozen_string_literal: true
require 'pg'
require_relative 'lib/nicherank'

if $PROGRAM_NAME == __FILE__
  begin
    credential_file, directory, output = ARGV
    raise 'Usage: qa_postgres.rb PRIVATE_ENV DATASET_DIR REPORT.json' unless output
    url = File.readlines(credential_file, chomp: true).find { |l| l.start_with?('DATABASE_URL=') }.split('=', 2).last
    db = PG.connect(url)
    checks = {
      'broken_professor_university_fk' => 'SELECT count(*) FROM professors p LEFT JOIN universities u ON u.id=p.university_id WHERE u.id IS NULL',
      'broken_authorship_fk' => 'SELECT count(*) FROM authorships a LEFT JOIN professors p ON p.id=a.professor_id LEFT JOIN papers w ON w.id=a.paper_id WHERE p.id IS NULL OR w.id IS NULL',
      'broken_alias_fk' => 'SELECT count(*) FROM author_aliases a LEFT JOIN professors p ON p.id=a.professor_id WHERE p.id IS NULL',
      'duplicate_authorship_pairs' => 'SELECT count(*) FROM (SELECT professor_id,paper_id FROM authorships GROUP BY 1,2 HAVING count(*)>1) q',
      'duplicate_dois' => "SELECT count(*) FROM (SELECT doi FROM papers WHERE doi IS NOT NULL AND doi<>'' GROUP BY doi HAVING count(*)>1) q",
      'alias_canonical_collisions' => 'SELECT count(*) FROM author_aliases a JOIN professors p ON p.openalex_id=a.alias_openalex_id',
      'unlinked_papers' => 'SELECT count(*) FROM papers w WHERE NOT EXISTS(SELECT 1 FROM authorships a WHERE a.paper_id=w.id)',
      'invalid_paper_types' => "SELECT count(*) FROM papers WHERE paper_type NOT IN ('article','conference-paper','preprint','book-chapter')",
      'rank_without_provenance' => 'SELECT count(*) FROM papers WHERE (venue_tier IS NULL) <> (venue_tier_source IS NULL)',
      'incorrect_search_vectors' => "SELECT count(*) FROM papers WHERE search_vector IS DISTINCT FROM (setweight(to_tsvector('english',coalesce(title,'')),'A') || setweight(to_tsvector('english',coalesce(keywords,'')),'A') || setweight(to_tsvector('english',coalesce(primary_topic,'')),'B') || setweight(to_tsvector('english',coalesce(abstract,'')),'C'))"
    }
    result = { 'checked_at' => Time.now.utc.iso8601, 'server_version' => db.exec('SHOW server_version').first.values.first,
               'checks' => checks.transform_values { |sql| db.exec(sql).first.values.first.to_i } }
    result['counts'] = %w[universities professors papers authorships author_aliases paper_duplicates data_review_cases].to_h { |table| [table, db.exec("SELECT count(*) FROM #{table}").first.fetch('count').to_i] }
    result['per_school'] = db.exec('SELECT u.name,count(DISTINCT p.id) AS professors,count(DISTINCT a.paper_id) AS papers,count(a.id) AS authorships FROM universities u LEFT JOIN professors p ON p.university_id=u.id LEFT JOIN authorships a ON a.professor_id=p.id GROUP BY u.id,u.name ORDER BY u.name').to_a
    result['zero_paper_professors'] = db.exec('SELECT p.openalex_id,p.name,u.name AS university FROM professors p JOIN universities u ON u.id=p.university_id WHERE NOT EXISTS(SELECT 1 FROM authorships a WHERE a.professor_id=p.id) ORDER BY u.name,p.name').to_a
    manifest = JSON.parse(File.read(File.join(directory, 'manifest.json')))
    result['extensions'] = db.exec("SELECT extname,extversion FROM pg_extension WHERE extname='vector'").to_a
    required = manifest.fetch('required_extensions', {})
    result['missing_required_extensions'] = required.keys - result['extensions'].map { |r| r['extname'] }
    if required.key?('vector') && result['missing_required_extensions'].empty?
      result['vector_smoke_distance'] = db.exec("SELECT '[1,2,3]'::vector <-> '[1,2,3]'::vector AS distance").first['distance'].to_f
    end
    result['manifest_counts'] = manifest.fetch('counts')
    expected_reviews = NicheRank.read_csv(File.join(directory, 'review.csv')).map { |r| Digest::SHA256.hexdigest(JSON.generate(r)) }.to_set
    result['preserved_legacy_review_cases'] = db.exec('SELECT fingerprint,issue_type,name_or_venue,status FROM data_review_cases').to_a.reject { |r| expected_reviews.include?(r['fingerprint']) }
    result['count_differences'] = manifest.fetch('counts').filter_map do |table, expected|
      destination = { 'duplicates' => 'paper_duplicates', 'review' => 'data_review_cases' }.fetch(table, table)
      actual = result['counts'].fetch(destination)
      permitted = expected == actual || (table == 'review' && actual == expected + result['preserved_legacy_review_cases'].size)
      { 'table' => destination, 'expected' => expected, 'actual' => actual } unless permitted
    end
    result['passed'] = result['checks'].values.all?(&:zero?) && result['count_differences'].empty? &&
      result['missing_required_extensions'].empty? && (!required.key?('vector') || result['vector_smoke_distance'] == 0.0)
    NicheRank.atomic_json(output, result)
    puts JSON.pretty_generate(result.slice('counts', 'checks', 'count_differences', 'passed'))
    exit(result['passed'] ? 0 : 1)
  rescue StandardError => e
    warn "Database QA failed (#{e.class}); credential-bearing diagnostics suppressed"
    exit 1
  ensure
    db&.close
  end
end
