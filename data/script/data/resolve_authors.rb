#!/usr/bin/env ruby
# frozen_string_literal: true

# Institution-pool matches plus targeted fallbacks. Outputs auditable proposals;
# canonical IDs are not called individually human-verified by this stage.
require_relative 'lib/nicherank'
require_relative 'scan_authors'

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  NicheRank.load_openalex_key(File.join(root, '.env.local'))
  manual = File.join(root, 'db/data/manual')
  output = File.join(root, 'tmp/author_resolution')
  schools = NicheRank.read_csv(File.join(manual, 'universities.csv')).to_h { |s| [s['name'], s] }
  people = NicheRank.read_csv(File.join(manual, 'faculty_raw.csv'))
  verified = NicheRank.read_csv(File.join(manual, 'author_matches.csv')).select { |p| p['status'] == 'verified' }.to_h { |p| [[p['university'], p['name']], p] }
  client = NicheRank::Client.new(cache: File.join(root, 'tmp/openalex_cache'), max_requests: 700)
  pools = schools.to_h do |name, school|
    path = File.join(root, "tmp/author_scan/#{school['openalex_id']}.json")
    [name, JSON.parse(File.read(path)).fetch('candidates')]
  end
  proposals, decisions, unresolved = [], [], []
  people.each_with_index do |person, index|
    school = schools.fetch(person['university'])
    candidates = pools.fetch(person['university']).fetch(person['name'], {}).dup
    best_score = candidates.values.map { |c| c['name_score'] }.max || 0
    if best_score < 3 && !verified.key?([person['university'], person['name']])
      results = client.get('authors', 'search' => person['name'], 'filter' => "affiliations.institution.id:#{school['openalex_id']}", 'per_page' => 10).fetch('results')
      results.each do |author|
        variants = [author['display_name'], *Array(author['display_name_alternatives'])].compact
        score = variants.map { |name| NicheRank::IdentityNames.score(person['name'], name) }.max || 0
        candidates[NicheRank.short_id(author['id'], 'A')] = { 'name_score' => score, 'author' => author, 'institution_search' => true } if score >= 2
      end
      if candidates.values.none? { |c| c['name_score'] >= 3 }
        client.get('authors', 'search' => person['name'], 'per_page' => 10).fetch('results').each do |author|
          variants = [author['display_name'], *Array(author['display_name_alternatives'])].compact
          score = variants.map { |name| NicheRank::IdentityNames.score(person['name'], name) }.max || 0
          next if score < 2
          affiliations = Array(author['last_known_institutions']) + Array(author['affiliations']).filter_map { |a| a['institution'] }
          at_school = affiliations.any? { |i| i['id'].to_s.end_with?("/#{school['openalex_id']}") }
          candidates[NicheRank.short_id(author['id'], 'A')] ||= { 'name_score' => score, 'author' => author, 'institution_search' => at_school, 'wide_only' => !at_school }
        end
      end
    end
    prior = verified[[person['university'], person['name']]]
    if prior && !candidates.key?(prior['openalex_id'])
      a = client.get("authors/#{prior['openalex_id']}")
      candidates[prior['openalex_id']] = { 'name_score' => 4, 'author' => a, 'prior_verified' => true }
    end
    eligible = candidates.reject { |_, c| c['wide_only'] || c['name_score'] < 3 }
    ranked = eligible.sort_by { |id, c| [-c['name_score'], -c['author'].fetch('works_count', 0), id] }
    selection = prior ? [prior['openalex_id'], candidates.fetch(prior['openalex_id'])] : ranked.first
    reason = nil
    if prior
      reason = 'previously reviewed sample match'
    elsif selection
      id, candidate = selection
      same_score = ranked.select { |_, c| c['name_score'] == candidate['name_score'] }
      same_orcid = !candidate['author']['orcid'].to_s.empty? && same_score.all? { |_, c| c['author']['orcid'] == candidate['author']['orcid'] }
      second = same_score[1]
      dominant = second && candidate['author'].fetch('works_count', 0) >= 5 * [second.last['author'].fetch('works_count', 0), 1].max
      if same_score.size == 1
        reason = 'unique strongest name match with institutional CS-profile evidence'
      elsif same_orcid
        reason = 'same-name profiles share the same primary ORCID; canonical checked in alias stage'
      elsif dominant && candidate['author'].fetch('works_count', 0) >= 30
        reason = 'dominant institutional name match; requires targeted QA review'
      end
    end
    if selection && reason
      id, candidate = selection
      proposals << { 'university' => person['university'], 'name' => person['name'], 'openalex_id' => id,
                     'match_confidence' => prior ? prior['match_confidence'] : candidate['name_score'] == 4 ? 'high' : 'medium',
                     'status' => prior ? 'verified' : 'proposed', 'evidence_url' => "#{person['homepage_url']}; https://openalex.org/#{id}",
                     'alias_checked_on' => prior ? prior['alias_checked_on'] : nil,
                     'notes' => "#{reason}; automated proposal, school spot-checks pending unless previously verified" }
      decisions << { 'university' => person['university'], 'name' => person['name'], 'selected_id' => id, 'reason' => reason,
                     'candidate_count' => candidates.size, 'candidate_ids' => candidates.keys, 'author' => candidate['author'], 'name_score' => candidate['name_score'] }
    else
      unresolved << { 'issue_type' => 'author_match', 'university' => person['university'], 'name_or_venue' => person['name'],
                      'candidate_ids' => candidates.keys.join('; '), 'reason' => 'No unambiguous supported match after institutional scan and targeted searches',
                      'status' => 'open', 'resolution' => nil }
    end
    if (index + 1) % 25 == 0 || index + 1 == people.size
      NicheRank.atomic_json(File.join(output, 'decisions.json'), decisions)
      NicheRank.write_csv(File.join(manual, 'author_match_proposals.csv'), %w[university name openalex_id match_confidence status evidence_url alias_checked_on notes], proposals)
      NicheRank.write_csv(File.join(output, 'unresolved.csv'), NicheRank::HEADERS['review'], unresolved)
      puts "#{index + 1}/#{people.size}: #{proposals.size} proposals, #{unresolved.size} unresolved; #{client.requests} live requests"
      $stdout.flush
    end
  end
end
