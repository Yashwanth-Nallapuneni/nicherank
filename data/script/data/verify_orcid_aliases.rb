#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'lib/nicherank'
require_relative 'scan_authors'

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  NicheRank.load_openalex_key(File.join(root, '.env.local'))
  accepted = NicheRank.read_csv(File.join(root, 'db/data/manual/accepted_author_matches.csv')).to_h { |r| [r['openalex_id'], r] }
  proposals = JSON.parse(File.read(File.join(root, 'tmp/orcid_alias_proposals.json')))
  coauthors = Hash.new { |h, k| h[k] = Set.new }
  Dir[File.join(root, 'tmp/openalex_cache/*.json')].each do |file|
    j = JSON.parse(File.read(file))
    next unless j['endpoint'] == 'works'
    Array(j.dig('response', 'results')).each do |work|
      authors = Array(work['authorships'])
      names = authors.map { |a| NicheRank::IdentityNames.key(a.dig('author', 'display_name')) }.reject(&:empty?)
      authors.each do |a|
        id = a.dig('author', 'id').to_s.split('/').last
        coauthors[id].merge(names) if accepted.key?(id)
      end
    end
  end
  puts "Canonical coauthor evidence assembled for #{coauthors.size} profiles"
  $stdout.flush
  client = NicheRank::Client.new(cache: File.join(root, 'tmp/openalex_cache'), max_requests: 180)
  old = NicheRank.read_csv(File.join(root, 'db/data/manual/author_aliases.csv'))
  approved = old.dup
  evidence = []
  protected_names = /Barrett|Goodman|Jiajun Wu/i
  proposals.each do |proposal|
    canonical, id = proposal.values_at('professor_openalex_id', 'alias_openalex_id')
    next unless accepted.key?(canonical)
    next if accepted.key?(id) || proposal['name'].match?(protected_names)
    author = proposal.fetch('author')
    score = NicheRank::IdentityNames.score(accepted.fetch(canonical)['name'], author['display_name'])
    next if score < 3
    path = File.join(root, "tmp/alias_verification/#{canonical}-#{id}.json")
    if File.exist?(path)
      result = JSON.parse(File.read(path))
    else
      works = client.get('works', 'filter' => "authorships.author.id:#{id},from_publication_date:2015-01-01", 'per_page' => 100,
                         'select' => 'id,title,authorships', 'sort' => 'publication_date:desc').fetch('results')
      names = works.flat_map { |w| Array(w['authorships']).map { |a| NicheRank::IdentityNames.key(a.dig('author', 'display_name')) } }.reject(&:empty?).to_set
      self_names = [accepted.fetch(canonical)['name'], author['display_name']].map { |n| NicheRank::IdentityNames.key(n) }.to_set
      shared = ((coauthors[canonical] & names) - self_names).to_a.sort
      result = proposal.slice('professor_openalex_id', 'name', 'alias_openalex_id', 'primary_orcid').merge('shared_coauthor_names' => shared,
        'sampled_alias_works' => works.map { |w| w['id'] }, 'approved' => shared.size >= 2,
        'reason' => 'Same primary ORCID + compatible display name + at least two shared coauthors; otherwise withheld')
      NicheRank.atomic_json(path, result)
    end
    approved << { 'professor_openalex_id' => canonical, 'alias_openalex_id' => id } if result['approved']
    evidence << result
    NicheRank.write_csv(File.join(root, 'db/data/manual/accepted_author_aliases.csv'), NicheRank::HEADERS['author_aliases'], approved.uniq)
    NicheRank.atomic_json(File.join(root, 'tmp/verified_alias_evidence.json'), evidence)
    puts "#{evidence.size} checked; #{approved.uniq.size} aliases accepted; #{client.requests} live requests"
    $stdout.flush
  end
end
