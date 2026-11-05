#!/usr/bin/env ruby
# frozen_string_literal: true

# Local checks only. Does not access GitHub, the network, or the key's value.
require_relative 'lib/nicherank'
root = File.expand_path('../..', __dir__)
manual = File.join(root, 'db/data/manual')
schools = NicheRank.read_csv(File.join(manual, 'universities.csv'))
roster = NicheRank.read_csv(File.join(manual, 'faculty_raw.csv'))
matches = NicheRank.read_csv(File.join(manual, 'author_matches.csv'))
aliases = NicheRank.read_csv(File.join(manual, 'author_aliases.csv'))
errors = []
schools.each do |school|
  next if school['openalex_id'].to_s.empty?
  errors << "Invalid institution ID for #{school['name']}" unless school['openalex_id'].match?(/\AI\d+\z/)
end
verified = matches.select { |m| m['status'] == 'verified' }
verified.each do |match|
  name = match['name']
  errors << "Invalid author ID for #{name}" unless match['openalex_id'].to_s.match?(/\AA\d+\z/)
  errors << "Missing confidence for #{name}" unless %w[high medium manual].include?(match['match_confidence'])
  errors << "Missing evidence for #{name}" if match['evidence_url'].to_s.empty?
  begin
    Date.iso8601(match.fetch('alias_checked_on').to_s)
  rescue ArgumentError
    errors << "Missing/invalid alias review date for #{name}"
  end
  school = schools.find { |u| u['name'] == match['university'] }
  errors << "Missing verified university ID for #{name}" unless school && school['openalex_id'].to_s.match?(/\AI\d+\z/)
  errors << "Missing roster row for #{name}" unless roster.any? { |r| r['name'] == name && r['university'] == match['university'] }
end
canonical_ids = verified.map { |m| m['openalex_id'] }
errors << 'Canonical IDs are not unique' unless canonical_ids.uniq == canonical_ids
alias_ids = aliases.map { |a| a['alias_openalex_id'] }
errors << 'Alias IDs are not unique' unless alias_ids.uniq == alias_ids
aliases.each do |a|
  errors << 'Invalid alias ID' unless a['alias_openalex_id'].to_s.match?(/\AA\d+\z/)
  errors << 'Alias conflicts with canonical ID' if canonical_ids.include?(a['alias_openalex_id'])
  errors << 'Alias has no verified canonical match' unless canonical_ids.include?(a['professor_openalex_id'])
end
puts "Configured schools: #{schools.size}"
puts "Schools with institution IDs: #{schools.count { |u| !u['openalex_id'].to_s.empty? }}"
puts "Eligible starter roster entries: #{roster.size} (not a complete roster)"
puts "Verified author matches: #{verified.size}"
puts "API key present: #{!ENV['OPENALEX_API_KEY'].to_s.empty?} (value never printed)"
puts "Data-input errors: #{errors.size}"
errors.each { |e| warn e }
puts 'Ready for local tests. Live collection needs a key and verified author matches.' if errors.empty?
exit(errors.empty? ? 0 : 1)
