#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/nicherank'
require_relative 'scan_authors'

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  NicheRank.load_openalex_key(File.join(root, '.env.local'))
  schools = NicheRank.read_csv(File.join(root, 'db/data/manual/universities.csv')).to_h { |u| [u['name'], u['openalex_id']] }
  cases = NicheRank.read_csv(File.join(root, 'tmp/author_resolution/unresolved.csv'))
  client = NicheRank::Client.new(cache: File.join(root, 'tmp/openalex_cache'), max_requests: 250)
  overrides = { 'Frederike Duembgen' => 'Frederike Dümbgen', 'Qi (Rose) Yu' => 'Rose Yu', 'YuFeng (Kevin) Chen' => 'Kevin Chen',
                'Ana Maria Sande do Vale Pinto da Silva' => 'Ana Silva', 'Ken Koedinger' => 'Kenneth Koedinger', 'Jim McCann' => 'James McCann',
                'Jim Rehg' => 'James Rehg', 'Russell Tedrake' => 'Russ Tedrake', 'Sasha Golovnev' => 'Alexander Golovnev',
                'Alex Rives' => 'Alexander Rives', 'Frederic Durand' => 'Fredo Durand', 'Richard M Stern Jr.' => 'Richard Stern',
                'Charles L. Isbell, Jr.' => 'Charles Isbell', 'Tom Costello' => 'Thomas Costello' }
  cases.each_with_index do |person, index|
    name = person['name_or_venue']
    fingerprint = Digest::SHA256.hexdigest([person['university'], name].join('|'))
    path = File.join(root, "tmp/author_refinement/#{fingerprint}.json")
    next if File.exist?(path) && JSON.parse(File.read(path))['complete']
    tokens = NicheRank::IdentityNames.tokens(name).reject { |t| t.match?(/\A\d+\z/) || %w[jr sr].include?(t) }
    query = overrides.fetch(name, [tokens.first, tokens.last].join(' '))
    candidates = {}
    filters = ["affiliations.institution.id:#{schools.fetch(person['university'])}", 'topics.field.id:17']
    filters.each do |filter|
      response = client.get('authors', 'search' => query, 'filter' => filter, 'per_page' => 100)
      response.fetch('results').each do |a|
        variants = [a['display_name'], *Array(a['display_name_alternatives'])]
        score = variants.map { |variant| [NicheRank::IdentityNames.score(name, variant), NicheRank::IdentityNames.score(query, variant)].max }.max || 0
        next if score < 2
        candidates[NicheRank.short_id(a['id'], 'A')] = { 'author' => a, 'score' => score, 'query' => query }
      end
    end
    NicheRank.atomic_json(path, { 'university' => person['university'], 'name' => name, 'query' => query, 'complete' => true, 'candidates' => candidates })
    puts "#{index + 1}/#{cases.size}: #{name}: #{candidates.size} refined candidates; #{client.requests} new requests"
    $stdout.flush
  end
end
