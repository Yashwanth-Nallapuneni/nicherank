#!/usr/bin/env ruby
# frozen_string_literal: true

# Iteration 2 identity acceptance for the fifteen added schools.
#
# Inputs: iteration2_author_match_proposals.csv (resolve_authors.rb with
# NICHE_SCOPE=iteration2), the resolver's unresolved list, and the roster.
# Outputs: new rows appended to accepted_author_matches.csv (existing rows are
# never rewritten) and iteration2_review.csv with every withheld case.
#
# Policy (same evidence standard as the automated baseline matches):
# - accept the resolver's unique / same-ORCID / dominant institutional match;
# - withhold an OpenAlex ID already used by another accepted professor, or
#   proposed for two roster people, instead of guessing which is correct;
# - withhold unresolved names and directory-eligibility cases as open reviews.
require_relative 'lib/nicherank'
require_relative 'lib/iteration_scope'

root = File.expand_path('../..', __dir__)
manual = File.join(root, 'db/data/manual')
scope = NicheRank::IterationScope.fetch(default: 'iteration2') # NICHE_SCOPE=iteration2_continued for the next batch
schools = scope.schools
headers = %w[university name openalex_id match_confidence status evidence_url alias_checked_on notes]

accepted_path = File.join(manual, 'accepted_author_matches.csv')
accepted = NicheRank.read_csv(accepted_path)
baseline = accepted.reject { |r| schools.include?(r['university']) }
roster_keys = NicheRank.read_csv(File.join(manual, 'faculty_raw.csv')).map { |r| [r['university'], r['name']] }.to_set
proposals = NicheRank.read_csv(File.join(manual, scope.proposals_file))
# Second-pass targeted matches (iteration2_retry.rb) for people the resolver left unresolved.
retry_path = File.join(manual, scope.retry_file)
retried = File.exist?(retry_path) ? NicheRank.read_csv(retry_path) : []
# Third pass (iteration2_continued_orcid_pass.rb); a name-search match from the second pass takes precedence.
orcid_path = File.join(manual, scope.orcid_file)
retried += NicheRank.read_csv(orcid_path).reject { |r| retried.any? { |x| x['university'] == r['university'] && x['name'] == r['name'] } } if File.exist?(orcid_path)
retried_keys = retried.map { |r| [r['university'], r['name']] }.to_set
proposals = proposals.reject { |r| retried_keys.include?([r['university'], r['name']]) } + retried.map { |r| r.slice('university', 'name', 'openalex_id', 'match_confidence', 'status', 'evidence_url', 'alias_checked_on', 'notes') }
# People later removed from the eligible roster (overrides) are not loaded.
proposals.select! { |r| roster_keys.include?([r['university'], r['name']]) }
candidates = NicheRank.read_csv(File.join(manual, 'faculty_candidates.csv')).select { |r| schools.include?(r['university']) }

institution = NicheRank.read_csv(File.join(manual, 'universities.csv')).to_h { |u| [u['name'], u['openalex_id']] }
# Profile-level guards using the full OpenAlex author record (collect_author_metadata.rb):
# a profile never affiliated with the school, or one so large it is almost certainly
# several people merged, is withheld rather than loaded.
profile_problem = lambda do |row|
  path = File.join(root, "tmp/author_metadata/#{row['openalex_id']}.json")
  raise "Missing author metadata for #{row['openalex_id']}; run collect_author_metadata.rb first" unless File.exist?(path)
  author = JSON.parse(File.read(path)).fetch('author')
  school = institution.fetch(row['university'])
  ids = (Array(author['last_known_institutions']) + Array(author['affiliations']).map { |a| a['institution'] }).map { |i| i.to_h['id'].to_s }
  # Recent hires from the second pass are reviewed individually (see
  # iteration2_identity_corrections.csv); OpenAlex still lists their previous school.
  recent_hire = row['notes'].to_s.include?('recent hire')
  next "Matched profile has no OpenAlex affiliation with #{row['university']}; likely a different person" unless recent_hire || ids.any? { |i| i.end_with?("/#{school}") }
  next "Matched profile has #{author['works_count']} works; likely several people merged into one OpenAlex profile" if author['works_count'].to_i > 2000
  nil
end

# Reviewed corrections from targeted topic/affiliation checks (see iteration2_identity_corrections.csv).
corrections_path = File.join(manual, scope.corrections_file)
corrections = File.exist?(corrections_path) ? NicheRank.read_csv(corrections_path).to_h { |r| [[r['university'], r['name']], r] } : {}
withheld_by_review = []
proposals = proposals.filter_map do |row|
  fix = corrections[[row['university'], row['name']]]
  next row unless fix
  case fix['decision']
  when 'replace'
    row.merge('openalex_id' => fix.fetch('openalex_id'), 'match_confidence' => 'manual',
              'evidence_url' => "#{row['evidence_url'].to_s.split('; ').first}; https://openalex.org/#{fix['openalex_id']}",
              'notes' => "Reviewed correction: #{fix['reason']}; automated proposal")
  when 'withhold'
    withheld_by_review << { 'issue_type' => 'author_match', 'university' => row['university'], 'name_or_venue' => row['name'],
                            'candidate_ids' => row['openalex_id'], 'reason' => fix['reason'], 'status' => 'open',
                            'resolution' => 'Withheld after review; no reliable OpenAlex profile' }
    nil
  else raise "Unknown correction decision #{fix['decision']}"
  end
end

used = baseline.to_h { |r| [r['openalex_id'], r] }
proposal_counts = proposals.group_by { |r| r['openalex_id'] }.transform_values(&:size)
new_rows, review = [], []
proposals.each do |row|
  id = row.fetch('openalex_id')
  if (other = used[id])
    review << { 'issue_type' => 'author_match', 'university' => row['university'], 'name_or_venue' => row['name'], 'candidate_ids' => id,
                'reason' => "Proposed OpenAlex ID is already the accepted profile of #{other['name']} (#{other['university']}); not loaded twice",
                'status' => 'open', 'resolution' => 'Withheld pending identity review' }
  elsif proposal_counts[id] > 1
    review << { 'issue_type' => 'author_match', 'university' => row['university'], 'name_or_venue' => row['name'], 'candidate_ids' => id,
                'reason' => 'Same OpenAlex ID proposed for more than one added-school roster entry; ambiguous',
                'status' => 'open', 'resolution' => 'Withheld pending identity review' }
  elsif (problem = profile_problem.call(row))
    review << { 'issue_type' => 'author_match', 'university' => row['university'], 'name_or_venue' => row['name'], 'candidate_ids' => id,
                'reason' => problem, 'status' => 'open', 'resolution' => 'Withheld pending identity review' }
  else
    new_rows << row.merge('status' => 'accepted',
                          'notes' => "#{row['notes'].to_s.sub(/; automated proposal.*\z/, '')}; automated institutional/name match (#{scope.label}); not individually human-verified")
  end
end
review.concat(withheld_by_review)
unresolved = NicheRank.read_csv(File.join(root, scope.resolution_dir, 'unresolved.csv'))
unresolved.reject! { |r| retried_keys.include?([r['university'], r['name_or_venue']]) || !roster_keys.include?([r['university'], r['name_or_venue']]) }
unresolved.each do |row|
  review << row.merge('status' => 'open', 'resolution' => 'No OpenAlex ID guessed; withheld pending identity review')
end
candidates.select { |r| r['eligibility_status'] == 'needs_review' }.each do |r|
  review << { 'issue_type' => 'faculty_eligibility', 'university' => r['university'], 'name_or_venue' => r['name'], 'candidate_ids' => nil,
              'reason' => [r['title'], r['eligibility_reason'], r['source_url']].reject { |v| v.to_s.empty? }.join('; '),
              'status' => 'open', 'resolution' => 'Omitted from eligible roster pending appointment confirmation' }
end

merged = baseline + new_rows.sort_by { |r| [r['university'], NicheRank.normalize(r['name'])] }
NicheRank.write_csv(accepted_path, headers, merged)
# accepted_author_matches.csv is a CRLF source file whose bytes are hashed for
# provenance (.gitattributes -text); keep its baseline bytes unchanged.
File.binwrite(accepted_path, File.binread(accepted_path).gsub(/\r?\n/, "\r\n"))
NicheRank.write_csv(File.join(manual, scope.review_file), NicheRank::HEADERS['review'], review)
puts "Baseline accepted rows kept: #{baseline.size}; #{scope.label} accepted: #{new_rows.size}; withheld/review: #{review.size}"
puts review.map { |r| r['issue_type'] }.tally
