#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'lib/nicherank'

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  manual = File.join(root, 'db/data/manual')
  headers = %w[university name openalex_id match_confidence status evidence_url alias_checked_on notes]
  roster = NicheRank.read_csv(File.join(manual, 'faculty_raw.csv'))
  proposals = NicheRank.read_csv(File.join(manual, 'author_match_proposals.csv')).to_h { |r| [[r['university'], r['name']], r] }
  overrides = NicheRank.read_csv(File.join(manual, 'identity_overrides.csv')).to_h { |r| [r['name'], r] }
  rejected = ['Ryan Huang', 'Will Perkins', 'Steve Mussmann']
  matches, unresolved = [], []
  roster.each do |person|
    name = person['name']
    next if name == 'Alberto Apostolico (1948-2015)'
    row = proposals[[person['university'], name]]&.dup
    row = nil if rejected.include?(name)
    if (override = overrides[name])
      row = { 'university' => person['university'], 'name' => name, 'openalex_id' => override.fetch('openalex_id'),
              'match_confidence' => 'manual', 'status' => 'accepted', 'evidence_url' => "#{person['homepage_url']}; https://openalex.org/#{override.fetch('openalex_id')}",
              'alias_checked_on' => nil, 'notes' => "#{override.fetch('reason')}; alternative IDs remain unmerged unless separately approved" }
    elsif row
      row['status'] = 'accepted' unless row['status'] == 'verified'
      row['notes'] = row['notes'].to_s.sub('; automated proposal, school spot-checks pending unless previously verified', '') + '; automated institutional/name match; identity audit recorded separately'
    end
    if row
      NicheRank.short_id(row.fetch('openalex_id'), 'A')
      matches << row
    else
      unresolved << { 'issue_type' => 'author_match', 'university' => person['university'], 'name_or_venue' => name,
                      'candidate_ids' => nil, 'reason' => 'No reliable complete author profile after institution, name-variant and publication checks; no guessed ID loaded', 'status' => 'open', 'resolution' => nil }
    end
  end
  duplicates = matches.group_by { |r| r['openalex_id'] }.select { |_, rows| rows.size > 1 }
  raise "Canonical ID reused: #{duplicates.keys.join(',')}" unless duplicates.empty?
  NicheRank.write_csv(File.join(manual, 'accepted_author_matches.csv'), headers, matches)
  NicheRank.write_csv(File.join(manual, 'identity_review_remaining.csv'), NicheRank::HEADERS['review'], unresolved)
  puts "#{matches.size} accepted identities, #{unresolved.size} unresolved, 1 deceased roster entry excluded"
  unresolved.each { |r| puts "#{r['university']}: #{r['name_or_venue']}" }
end
