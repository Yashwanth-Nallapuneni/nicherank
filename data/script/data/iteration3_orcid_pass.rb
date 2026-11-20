#!/usr/bin/env ruby
# frozen_string_literal: true

# Third identity pass for faculty the resolver and the name-search retry could not match.
# CSRankings' public faculty list (csrankings.csv) carries an ORCID for many people; an ORCID names one
# person, so the OpenAlex profile with that ORCID is looked up directly. A profile is accepted only when
# ALL hold (the same evidence standard as the retry pass):
#   - a compatible display name (same surname; first name equal or one a prefix of the other),
#   - an OpenAlex affiliation with the school in 2020 or later (or the school as last known institution),
#   - Computer Science or Mathematics among its top-3 topic fields,
#   - between 3 and 2000 works, and the profile is not already another accepted professor's.
# Output: db/data/manual/<scope>_orcid_proposals.csv (read by iteration2_accept.rb) and
# tmp/<scope>/orcid_evidence.json. Nothing is guessed: everyone else stays in the review file.
# Usage: NICHE_SCOPE=iteration3 ruby script/data/iteration3_orcid_pass.rb [csrankings.csv]
require_relative 'lib/nicherank'
require_relative 'scan_authors'
require_relative 'lib/iteration_scope'
require_relative 'build_homepage_fallbacks'

root = File.expand_path('../..', __dir__)
NicheRank.load_openalex_key(File.join(root, '.env.local'))
manual = File.join(root, 'db/data/manual')
scope = NicheRank::IterationScope.fetch(default: 'iteration3')
csr_path = ARGV[0] || File.join(root, 'tmp/iteration3/gap/csrankings.csv')
abort "CSRankings file not found: #{csr_path}" unless File.exist?(csr_path)

schools = NicheRank.read_csv(File.join(manual, 'universities.csv')).to_h { |u| [u['name'], u['openalex_id']] }
roster = NicheRank.read_csv(File.join(manual, 'faculty_raw.csv')).to_h { |r| [[r['university'], r['name']], r] }
accepted = NicheRank.read_csv(File.join(manual, 'accepted_author_matches.csv'))
used_ids = accepted.to_h { |r| [r['openalex_id'], r] }
review = NicheRank.read_csv(File.join(manual, scope.review_file)).select { |r| r['issue_type'] == 'author_match' && r['reason'].to_s.start_with?('No unambiguous') }
csrankings = NicheRank.read_csv(csr_path).group_by { |r| r['affiliation'] }
client = NicheRank::Client.new(cache: File.join(root, 'tmp/openalex_cache'), max_requests: 600)
computing = ['Computer Science', 'Mathematics']

first_ok = lambda do |a, b|
  x, y = NicheRank::IdentityNames.tokens(a).first.to_s, NicheRank::IdentityNames.tokens(b).first.to_s
  x == y || (x.size >= 3 && y.size >= 3 && (x.start_with?(y) || y.start_with?(x))) || (x[0] == y[0] && [x.size, y.size].min == 1)
end
name_ok = lambda do |roster_name, author|
  names = [author['display_name'], *Array(author['display_name_alternatives'])].compact
  mine = NicheRank::IdentityNames.tokens(roster_name)
  # the surnames agree, or one name's surname is part of the other (compound surnames such as Ordonez-Roman)
  names.any? do |n|
    theirs = NicheRank::IdentityNames.tokens(n)
    surname = theirs.last == mine.last || (theirs.size > 1 && mine.size > 1 && (mine.include?(theirs.last) || theirs.include?(mine.last)))
    surname && first_ok.call(roster_name, n)
  end
end

proposals, evidence = [], []
review.each do |c|
  name, university = c['name_or_venue'], c['university']
  next unless roster.key?([university, name])
  pool = (csrankings[NicheRank::HomepageFallbacks::AFFILIATION[university]] || []).select { |p| NicheRank::HomepageFallbacks.same?(name, p['name']) }
  orcids = pool.map { |p| p['orcid'].to_s.strip }.reject { |o| o.empty? || o.delete('0-') .empty? }.uniq
  next unless orcids.size == 1
  orcid = orcids.first
  profiles = begin
    client.get('authors', 'filter' => "orcid:#{orcid}", 'per_page' => 5,
               'select' => 'id,display_name,display_name_alternatives,orcid,works_count,affiliations,last_known_institutions,topics').fetch('results')
  rescue StandardError => e
    evidence << { 'university' => university, 'name' => name, 'orcid' => orcid, 'decision' => "lookup failed: #{e.message[0, 60]}" }
    next
  end
  school = schools.fetch(university)
  judged = profiles.map do |a|
    aid = NicheRank.short_id(a['id'], 'A')
    years = Array(a['affiliations']).select { |af| af.dig('institution', 'id').to_s.end_with?("/#{school}") }.flat_map { |af| Array(af['years']) }
    last_known = Array(a['last_known_institutions']).any? { |i| i['id'].to_s.end_with?("/#{school}") }
    fields = Array(a['topics']).first(3).map { |t| t.dig('field', 'display_name') }
    checks = { 'name' => name_ok.call(name, a), 'recent_school_affiliation' => last_known || years.any? { |y| y.to_i >= 2020 },
               'computing_topics' => (fields & computing).any?, 'works_3_to_2000' => a['works_count'].to_i.between?(3, 2000),
               'not_another_professors' => !used_ids.key?(aid) }
    { 'author' => a, 'id' => aid, 'checks' => checks, 'ok' => checks.values.all? }
  end
  best = judged.select { |j| j['ok'] }.max_by { |j| [j['author']['works_count'].to_i, j['id']] }
  shown = best || judged.first
  if shown.nil?
    evidence << { 'university' => university, 'name' => name, 'orcid' => orcid, 'decision' => 'rejected: no OpenAlex profile carries this ORCID' }
    next
  end
  author, id, checks = shown['author'], shown['id'], shown['checks']
  ok = !best.nil?
  evidence << { 'university' => university, 'name' => name, 'orcid' => orcid, 'openalex_id' => id, 'display_name' => author['display_name'], 'works' => author['works_count'],
                'profiles_with_this_orcid' => judged.size, 'checks' => checks,
                'decision' => ok ? 'accepted' : "rejected: #{checks.reject { |_, v| v }.keys.join(', ')}" }
  next unless ok
  homepage = roster.fetch([university, name])['homepage_url']
  proposals << { 'university' => university, 'name' => name, 'openalex_id' => id, 'match_confidence' => 'high', 'status' => 'proposed',
                 'evidence_url' => [homepage, "https://openalex.org/#{id}", "https://orcid.org/#{orcid}"].reject { |v| v.to_s.empty? }.join('; '), 'alias_checked_on' => nil,
                 'notes' => 'ORCID from the CSRankings public faculty list matches the OpenAlex profile; compatible name, recent school affiliation and computing topics; automated proposal' }
end
FileUtils.mkdir_p(File.join(root, scope.tmp_dir))
NicheRank.atomic_json(File.join(root, scope.tmp_dir, 'orcid_evidence.json'), evidence)
NicheRank.write_csv(File.join(manual, scope.orcid_file), %w[university name openalex_id match_confidence status evidence_url alias_checked_on notes], proposals)
puts "ORCID pass: #{review.size} withheld people; with a usable CSRankings ORCID: #{evidence.size}; accepted: #{proposals.size}; live requests: #{client.requests}"
puts evidence.map { |e| e['decision'].sub(/\Arejected: .*/, 'rejected') }.tally
