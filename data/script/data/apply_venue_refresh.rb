#!/usr/bin/env ruby
# frozen_string_literal: true
# Apply only reviewed paper-tier changes and current review/manifest metadata.
# No bibliography reload, deletion, identity changes or network source reads.
require 'pg'
require_relative 'lib/nicherank'
root=File.expand_path('../..',__dir__)
credential,report_path=ARGV
abort('Usage: apply_venue_refresh.rb PRIVATE_ENV REPORT.json') unless report_path
url=File.readlines(credential,chomp:true).find{|l|l.start_with?('DATABASE_URL=')}&.split('=',2)&.last
abort('Missing private DATABASE_URL') if url.to_s.empty?
db=nil
begin
 db=PG.connect(url)
 changes=NicheRank.read_csv(File.join(root,'reports/venues/paper_tier_changes.csv'))
 reviews=NicheRank.read_csv(File.join(root,'data/output/full/review.csv'))
 manifest=JSON.parse(File.read(File.join(root,'data/output/full/manifest.json')))
 result={'changed_papers'=>0,'input_paper_changes'=>changes.size,'scope'=>'venue tiers, review statuses and dataset metadata only'}
 db.transaction do
  db.exec("SET LOCAL lock_timeout='15s'")
  db.exec("SELECT pg_advisory_xact_lock(hashtext('nicherank-data-load'))")
  db.exec('CREATE TEMP TABLE venue_patch(openalex_id text PRIMARY KEY,venue text,tier text,source text) ON COMMIT DROP')
  db.copy_data('COPY venue_patch FROM STDIN WITH (FORMAT csv)') do
   changes.each do |r|
    NicheRank.short_id(r['openalex_id'],'W');raise 'Invalid tier' unless NicheRank::TIERS.include?(r['after']);raise 'Invalid provenance' unless %w[core2023 custom].include?(r['venue_tier_source'])
    db.put_copy_data(CSV.generate_line(r.values_at('openalex_id','venue','after','venue_tier_source')))
   end
  end
  matches=db.exec("SELECT count(*) FROM venue_patch s JOIN public.papers p USING(openalex_id) WHERE p.venue IS NOT DISTINCT FROM s.venue AND p.paper_type IN ('article','conference-paper')").first['count'].to_i
  raise 'Snapshot changed: tier patch no longer matches loaded papers' unless matches==changes.size
  result['changed_papers']=db.exec("UPDATE public.papers p SET venue_tier=s.tier,venue_tier_source=s.source,updated_at=now() FROM venue_patch s WHERE p.openalex_id=s.openalex_id AND (p.venue_tier,p.venue_tier_source) IS DISTINCT FROM (s.tier,s.source)").cmd_tuples
  headers=NicheRank::HEADERS['review'];db.exec("CREATE TEMP TABLE review_patch(fingerprint text,#{headers.map{|h|"#{h} text"}.join(',')}) ON COMMIT DROP")
  db.copy_data('COPY review_patch FROM STDIN WITH (FORMAT csv)') do
   reviews.each{|r|db.put_copy_data(CSV.generate_line([Digest::SHA256.hexdigest(JSON.generate(r)),*headers.map{|h|r[h]}]))}
  end
  columns=['fingerprint',*headers]
  db.exec("INSERT INTO public.data_review_cases(#{columns.join(',')}) SELECT #{columns.join(',')} FROM review_patch WHERE true ON CONFLICT(fingerprint) DO NOTHING")
  db.exec("UPDATE public.data_review_cases r SET status='superseded',resolution='Resolved by the venue coverage refresh; newer current review case retained' WHERE r.issue_type='venue_match' AND r.status='open' AND EXISTS(SELECT 1 FROM review_patch s WHERE s.issue_type='venue_match' AND s.status='closed' AND s.name_or_venue=r.name_or_venue) AND NOT EXISTS(SELECT 1 FROM review_patch s WHERE s.fingerprint=r.fingerprint)")
  key="#{manifest.fetch('scope')}-#{manifest.fetch('collection_cutoff')}"
  db.exec_params('UPDATE public.dataset_metadata SET manifest=$1::jsonb,loaded_at=now() WHERE dataset_key=$2',[JSON.generate(manifest),key])
 end
 result['tier_coverage']=db.exec("SELECT paper_type,count(*) AS total,count(venue_tier) AS ranked,count(*) FILTER(WHERE venue_tier IS NULL) AS unranked FROM papers GROUP BY paper_type ORDER BY paper_type").to_a
 result['vector']=db.exec("SELECT extversion,'[1,2,3]'::vector <-> '[1,2,3]'::vector AS zero_distance FROM pg_extension WHERE extname='vector'").first
 result['checked_at']=Time.now.utc.iso8601
 NicheRank.atomic_json(report_path,result);puts JSON.pretty_generate(result)
rescue StandardError=>e
 warn "Venue refresh failed (#{e.class}); transaction rolled back; connection details suppressed";exit 1
ensure
 db&.close
end
