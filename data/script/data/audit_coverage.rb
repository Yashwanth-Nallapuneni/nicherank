#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'lib/nicherank'
root=File.expand_path('../..',__dir__)
NicheRank.load_openalex_key(File.join(root,'.env.local'))
client=NicheRank::Client.new(cache:File.join(root,'tmp/openalex_cache'),max_requests:70)
hints=NicheRank.read_csv(File.join(root,'reports/audit/reference_hints.csv'))
needed=NicheRank.read_csv(File.join(root,'db/data/manual/identity_review_remaining.csv')).map{|r|r['name_or_venue']} + %w[Christoforos\ Kozyrakis]
orcids=hints.select{|r|needed.include?(r['name']) || r['orcid_conflict']=='True'}.map{|r|r['reference_orcid']}.reject{|s|s.to_s.empty?}.uniq
orcids.each_slice(40).with_index do |batch,i|
 response=client.get('authors',{'filter'=>"orcid:#{batch.join('|')}",'per_page'=>100})
 NicheRank.atomic_json(File.join(root,"tmp/audit/reference_orcid_profiles_#{i}.json"),response)
 puts "ORCID batch #{i}: #{response.fetch('results').size} profiles";$stdout.flush
end
queries={'Stephen Mussmann'=>'Stephen Mussmann','Ana Maria Pinto da Silva'=>'Ana Maria Pinto da Silva','Ari Lightman'=>'Ari Lightman','Dimi Apostolopoulos'=>'Dimi Apostolopoulos'}
queries.each do |name,query|
 r=client.get('authors',{'search'=>query,'per_page'=>100})
 NicheRank.atomic_json(File.join(root,"tmp/audit/#{Digest::SHA256.hexdigest(name)}.json"),{'query'=>query,'results'=>r.fetch('results')})
 puts "Name #{name}: #{r.fetch('results').size}";$stdout.flush
end
papers={
'Michael Kim'=>['Multiaccuracy Black Box Post Processing for Fairness in Classification','https://www.cs.cornell.edu/~mpkim/pubs.html'],
'Will Perkins'=>['Counting independent sets in cubic graphs','https://willperkins.org/'],
'Steve Mussmann'=>['On the Relationship between Data Efficiency and Error for Uncertainty Sampling','https://steve.mussmann.us/'],
'Yiying Zhang'=>['LegoOS a Disseminated Distributed OS for Hardware Resource Disaggregation','https://cseweb.ucsd.edu/~yiying/'],
'Qi Tang'=>['An adaptive scalable fully implicit algorithm based on stabilized finite element for reduced visco resistive MHD','https://tangqi.github.io/publications/'],
'Bo Li'=>['DecodingTrust A Comprehensive Assessment of Trustworthiness in GPT Models','https://aisecure.github.io/'],
'Gang Wang'=>['Email Spoofing with SMTP Smuggling How the Shared Email Infrastructures Magnify this Vulnerability','https://gangw.cs.illinois.edu/'],
'Wei Hu'=>['On Exact Computation with an Infinitely Wide Neural Net','https://weihu.me/'],
'Hao Peng'=>['Towards a Universal Causal Reasoner','https://haopeng-nlp.github.io/'],
'Tom Costello'=>['Durably reducing conspiracy beliefs through dialogues with AI','https://thcostello.com/'],
'Christoforos Kozyrakis'=>['Paragon QoS Aware Scheduling for Heterogeneous Datacenters','https://mast.stanford.edu/']}
papers.each do |name,(query,source)|
 path=File.join(root,"tmp/audit/paper_anchor_#{Digest::SHA256.hexdigest(name)}.json")
 next if File.exist?(path)
 r=client.get('works',{'search'=>query,'per_page'=>5,'select'=>'id,title,authorships,doi,publication_year'})
 NicheRank.atomic_json(path,{'name'=>name,'query'=>query,'source'=>source,'results'=>r.fetch('results')})
 puts "Paper #{name}: #{r.fetch('results').size}";$stdout.flush
end
