#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'lib/nicherank'
root=File.expand_path('../..',__dir__)
output=File.join(root,'data/output/full');manual=File.join(root,'db/data/manual');report=File.join(root,'reports/venues')
backup=File.join(root,'tmp/venue_refresh/baseline_v2')
FileUtils.mkdir_p(backup)
%w[papers.csv review.csv manifest.json].each{|name|FileUtils.cp(File.join(output,name),File.join(backup,name)) unless File.exist?(File.join(backup,name))}
tiers=NicheRank.read_csv(File.join(manual,'venue_tiers.csv')).to_h{|r|[NicheRank.normalize(r['venue']),r]}
papers=NicheRank.read_csv(File.join(output,'papers.csv'));changes=[]
papers.each do |paper|
 next unless %w[article proceedings-article].include?(paper['type'])
 mapping=tiers[NicheRank.normalize(paper['venue'])]
 next unless mapping && paper['venue_tier']!=mapping['venue_tier']
 changes<<{'openalex_id'=>paper['openalex_id'],'paper_type'=>paper['type']=='proceedings-article' ? 'conference-paper' : paper['type'],'venue'=>paper['venue'],'before'=>paper['venue_tier'],'after'=>mapping['venue_tier'],'venue_tier_source'=>mapping['kind']=='conference' ? 'core2023' : 'custom'}
 paper['venue_tier']=mapping['venue_tier']
end
NicheRank.write_csv(File.join(output,'papers.csv'),NicheRank::HEADERS['papers'],papers)
changefile=File.join(report,'paper_tier_changes.csv')
previous=File.exist?(changefile) ? NicheRank.read_csv(changefile) : []
NicheRank.write_csv(changefile,%w[openalex_id paper_type venue before after venue_tier_source],(previous+changes).uniq{|r|r['openalex_id']})
reviews=NicheRank.read_csv(File.join(output,'review.csv'));closed=0
reviews.each do |row|
 next unless row['issue_type']=='venue_match'
 mapping=tiers[NicheRank.normalize(row['name_or_venue'])]
 next unless mapping
 row['status']='closed';row['resolution']="Exact venue mapping: #{mapping['venue_tier']} (#{mapping['kind']=='conference' ? 'core2023' : 'custom'}); #{mapping['source']}";closed+=1
end
NicheRank.write_csv(File.join(output,'review.csv'),NicheRank::HEADERS['review'],reviews)
coverage=papers.group_by{|r|r['type']=='proceedings-article' ? 'conference-paper' : r['type']}.transform_values do |rows|
 ranked=rows.count{|r|!r['venue_tier'].to_s.empty?}
 {'total'=>rows.size,'ranked'=>ranked,'unranked'=>rows.size-ranked,'coverage_percent'=>(100.0*ranked/rows.size).round(2)}
end
NicheRank.atomic_json(File.join(report,'coverage_after.json'),coverage)
unmapped=papers.select{|r|%w[article proceedings-article].include?(r['type']) && r['venue_tier'].to_s.empty?}.group_by{|r|[r['type']=='proceedings-article' ? 'conference-paper' : r['type'],r['venue']]}.map{|(type,venue),rows|{'paper_type'=>type,'venue'=>venue,'papers'=>rows.size}}.sort_by{|r|-r['papers']}
NicheRank.write_csv(File.join(report,'missing_after.csv'),%w[paper_type venue papers],unmapped)
manifest=JSON.parse(File.read(File.join(output,'manifest.json')))
manifest['venue_enrichment_revision']=1;manifest['required_extensions']={'vector'=>'0.8.0'};manifest['tier_coverage']=coverage
manifest['manual_input_sha256']=Dir[File.join(manual,'*.csv')].sort.to_h{|f|[File.basename(f),Digest::SHA256.file(f).hexdigest]}
manifest['export_sha256']=Dir[File.join(output,'*.csv')].sort.to_h{|f|[File.basename(f),Digest::SHA256.file(f).hexdigest]}
NicheRank.atomic_json(File.join(output,'manifest.json'),manifest)
errors=NicheRank::Validator.new(output,allow_empty_professors:true).errors;raise errors.join('; ') unless errors.empty?
puts JSON.pretty_generate({'papers_changed'=>changes.size,'venue_review_cases_resolved'=>closed,'coverage'=>coverage})
