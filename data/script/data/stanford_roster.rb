#!/usr/bin/env ruby
# frozen_string_literal: true

# Parse a downloaded Stanford directory page locally; no network or API key.
# Page-specific extraction intentionally fails on layout changes. Eligibility still
# requires review: courtesy affiliations and named chairs need human judgment.
require 'cgi'
require_relative 'lib/nicherank'

module NicheRank
  module StanfordRoster
    SOURCE = 'https://www.cs.stanford.edu/people/faculty'
    HEADERS = %w[university name title homepage_url source_url]
    def self.extract(html)
      html.scan(%r{<div class="su-card__contents">\s*<h3[^>]*>\s*<a href="([^"]+)">([^<]+)</a>\s*</h3>(.*?)</div>}m).map do |path, name, raw_title|
        title = CGI.unescapeHTML(raw_title.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip)
        name = CGI.unescapeHTML(name.strip)
        { 'university' => 'Stanford University', 'name' => name, 'title' => title,
          'homepage_url' => URI.join(SOURCE, path).to_s, 'source_url' => SOURCE }
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: ruby script/data/stanford_roster.rb DOWNLOADED_HTML OUTPUT_DIRECTORY' unless ARGV.size == 2
  rows = NicheRank::StanfordRoster.extract(File.read(ARGV[0]))
  abort 'No faculty cards found; inspect directory layout before proceeding' if rows.empty?
  directory = ARGV[1]
  NicheRank.write_csv(File.join(directory, 'stanford_roster_candidates.csv'), NicheRank::StanfordRoster::HEADERS + %w[eligibility_status notes],
                     rows.map { |row| row.merge('eligibility_status' => 'needs_review', 'notes' => 'Directory page only; profile URL used as homepage pending verification') })
  puts "Extracted #{rows.size} candidates; NOT a verified faculty roster. Follow directory pagination before claiming complete coverage."
end
