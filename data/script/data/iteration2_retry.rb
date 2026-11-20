#!/usr/bin/env ruby
# frozen_string_literal: true

# Second-pass identity search for added-school faculty the resolver could not
# match. Several name variants are searched; a candidate is accepted only with
# all of: a compatible display name, an OpenAlex affiliation with the school in 2020 or
# later, Computer Science or Mathematics among the top-3 topics, 5-600 works, and being the only
# such candidate or sharing the ORCID of / having 5x the works of every rival.
# Output: db/data/manual/iteration2_retry_proposals.csv (consumed by
# iteration2_accept.rb) plus tmp/iteration2/retry_evidence.json.
require_relative 'lib/nicherank'
require_relative 'scan_authors'
require_relative 'lib/iteration_scope'

root = File.expand_path('../..', __dir__)
NicheRank.load_openalex_key(File.join(root, '.env.local'))
manual = File.join(root, 'db/data/manual')
scope = NicheRank::IterationScope.fetch(default: 'iteration2') # NICHE_SCOPE=iteration3 for the next batch
schools = NicheRank.read_csv(File.join(manual, 'universities.csv')).to_h { |u| [u['name'], u['openalex_id']] }
roster = NicheRank.read_csv(File.join(manual, 'faculty_raw.csv')).to_h { |r| [[r['university'], r['name']], r] }
baseline_ids = NicheRank.read_csv(File.join(manual, 'accepted_author_matches.csv'))
                        .reject { |r| scope.schools.include?(r['university']) }.map { |r| r['openalex_id'] }.to_set
cases = NicheRank.read_csv(File.join(root, scope.resolution_dir, 'unresolved.csv'))
# Also retry people withheld for other reasons (collisions, wrong-person matches).
review_path = File.join(manual, scope.review_file) # written by the accept step; absent on the first pass
withheld = File.exist?(review_path) ? NicheRank.read_csv(review_path).select { |r| r['issue_type'] == 'author_match' } : []
cases = (cases + withheld).uniq { |c| [c['university'], c['name_or_venue']] }
cases.select! { |c| roster.key?([c['university'], c['name_or_venue']]) }
client = NicheRank::Client.new(cache: File.join(root, 'tmp/openalex_cache'), max_requests: 1500)
computing = ['Computer Science', 'Mathematics']

# Reviewed spelling variants for names the directory writes differently from publications.
known_variants = {
  'Satish Kumar Thittamaranahalli' => ['T. K. Satish Kumar', 'Satish Kumar'],
  'Jyo Deshmukh' => ['Jyotirmoy Deshmukh', 'Jyotirmoy V. Deshmukh'], 'Bill Press' => ['William H. Press'],
  'Brad Knox' => ['W. Bradley Knox'], 'Ed Amoroso' => ['Edward Amoroso'], 'Rob Johnson' => ['Robert Johnson', 'Rob Johnson'],
  'Vangelis Kalogerakis' => ['Evangelos Kalogerakis'], 'Steve Holtzen' => ['Steven Holtzen'], 'Mike Hagenow' => ['Michael Hagenow'],
  'Manolis Vlatakis' => ['Emmanouil-Vasileios Vlatakis-Gkaragkounis', 'Emmanouil Vlatakis-Gkaragkounis'],
  'Alan Zaoxing Liu' => ['Zaoxing Liu'], 'Zhuoqing Morley Mao' => ['Z. Morley Mao', 'Zhuoqing Morley Mao'],
  'Xiang (Jenny) Ren' => ['Xiang Ren'], 'Remy Wang' => ['Yisu Remy Wang'], 'Itsik G Pe\'er' => ['Itsik Pe\'er'],
  'Daniel Katz-Braunschweig' => ['Daniel Katz'], 'Juan Perdomo Silva' => ['Juan Carlos Perdomo', 'Juan C. Perdomo'],
  'Christos H Papadimitriou' => ['Christos H. Papadimitriou'], 'Ed K Wong' => ['Edward K. Wong'], 'Nick Hunter-Jones' => ['Nicholas Hunter-Jones'],
  'Josh Fried' => ['Joshua Fried'], 'Kexin Pei' => ['Kexin Pei'], 'Michael Franklin' => ['Michael J. Franklin']
}

def variants(name, known)
  base = name.gsub(/["“”]/, '').strip
  list = [name, base, base.gsub(/\s*\([^)]*\)\s*/, ' ').squeeze(' ').strip]
  if (nick = base[/\(([^)]+)\)/, 1])
    list << "#{nick} #{base.split.last}"
  end
  tokens = base.gsub(/\([^)]*\)/, '').split
  list << [tokens.first, tokens.last].join(' ') if tokens.size > 2
  (list + known.fetch(name, [])).map(&:strip).reject(&:empty?).uniq
end

coauthor_names = lambda do |id|
  works = client.get('works', 'filter' => "authorships.author.id:#{id},from_publication_date:2015-01-01", 'per_page' => 100,
                     'select' => 'id,authorships').fetch('results')
  works.flat_map { |w| Array(w['authorships']).map { |a| NicheRank::IdentityNames.key(a.dig('author', 'display_name')) } }.reject(&:empty?).to_set
end
# Several same-name school/computing profiles are treated as one person only when
# every smaller one shares at least three coauthors (other than the person) with the largest.
split_of_one_person = lambda do |name, ranked|
  next false if ranked.size > 4
  self_keys = ([name] + ranked.map { |r| r['display_name'] }).map { |n| NicheRank::IdentityNames.key(n) }.to_set
  largest = coauthor_names.call(ranked.first['id']) - self_keys
  ranked.drop(1).all? { |r| ((coauthor_names.call(r['id']) - self_keys) & largest).size >= 3 }
end

proposals, evidence = [], []
cases.each_with_index do |c, index|
  name, university = c['name_or_venue'], c['university']
  school = schools.fetch(university)
  queries = variants(name, known_variants)
  found = {}
  queries.each do |q|
    client.get('authors', 'search' => q, 'per_page' => 25).fetch('results').each do |a|
      id = NicheRank.short_id(a['id'], 'A')
      names = [a['display_name'], *Array(a['display_name_alternatives'])].compact
      score = queries.product(names).map { |x, y| NicheRank::IdentityNames.score(x, y) }.max || 0
      own = queries.map { |x| NicheRank::IdentityNames.score(x, a['display_name']) }.max || 0
      score = 0 if own < 3
      next if score < 3 || found.key?(id)
      years = Array(a['affiliations']).select { |af| af.dig('institution', 'id').to_s.end_with?("/#{school}") }.flat_map { |af| Array(af['years']) }
      last_known = Array(a['last_known_institutions']).any? { |i| i['id'].to_s.end_with?("/#{school}") }
      fields = Array(a['topics']).first(3).map { |t| t.dig('field', 'display_name') }
      found[id] = { 'id' => id, 'display_name' => a['display_name'], 'score' => score, 'own_score' => own, 'works' => a['works_count'].to_i,
                    'orcid' => a['orcid'], 'school_recent' => last_known || years.any? { |y| y.to_i >= 2020 },
                    'computing' => (fields & computing).any?, 'baseline_conflict' => baseline_ids.include?(id) }
    end
  end
  eligible = found.values.select { |f| f['school_recent'] && f['computing'] && f['works'].between?(5, 600) && !f['baseline_conflict'] }
  ranked = eligible.sort_by { |f| [-f['works'], f['id']] }
  best, rival = ranked[0], ranked[1]
  # Recent hires: OpenAlex affiliation often still shows the previous school.
  exact = found.values.select { |f| f['own_score'] == 4 && f['computing'] && f['works'].between?(10, 600) && !f['baseline_conflict'] }
  recent_hire = best.nil? && exact.size == 1 && found.values.none? { |f| f != exact.first && f['computing'] && f['works'] >= 5 }
  best = exact.first if recent_hire
  decision = if recent_hire
               'accepted: recent hire; the only exact-name computing profile (OpenAlex affiliation not yet updated)'
             elsif best.nil?
               'no candidate with recent school affiliation and computing topics'
             elsif rival.nil?
               'accepted: only candidate with compatible name, recent school affiliation and computing topics'
             elsif best['orcid'] && ranked.drop(1).all? { |r| r['orcid'] == best['orcid'] }
               'accepted: rival profiles share the same ORCID (split profile); largest kept'
             elsif best['works'] >= 5 * [rival['works'], 1].max && best['works'] >= 30
               'accepted: dominant candidate (5x the works of any rival) with recent school affiliation'
             elsif split_of_one_person.call(name, ranked)
               'accepted: every qualifying profile shares 3+ coauthors with the largest (one person split by OpenAlex); largest kept'
             else
               'ambiguous: several plausible profiles; not guessed'
             end
  evidence << { 'university' => university, 'name' => name, 'queries' => queries, 'decision' => decision, 'candidates' => found.values }
  if decision.start_with?('accepted')
    proposals << { 'university' => university, 'name' => name, 'openalex_id' => best['id'], 'match_confidence' => 'medium', 'status' => 'proposed',
                   'evidence_url' => "#{roster.fetch([university, name])['homepage_url']}; https://openalex.org/#{best['id']}", 'alias_checked_on' => nil,
                   'notes' => "Second-pass targeted search (#{best['display_name']}, #{best['works']} works): #{decision.sub('accepted: ', '')}" }
  end
  puts "#{index + 1}/#{cases.size} #{name}: #{decision}"
  $stdout.flush
end
FileUtils.mkdir_p(File.join(root, scope.tmp_dir))
NicheRank.atomic_json(File.join(root, scope.retry_evidence_file), evidence)
NicheRank.write_csv(File.join(manual, scope.retry_file), %w[university name openalex_id match_confidence status evidence_url alias_checked_on notes], proposals)
puts "Second pass: #{proposals.size}/#{cases.size} matched; #{client.requests} live requests"
