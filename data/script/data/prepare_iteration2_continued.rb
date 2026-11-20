#!/usr/bin/env ruby
# frozen_string_literal: true

# Iteration 2 (continued) roster preparation. Fetches the registered official directory pages
# (db/data/manual/iteration2_continued_sources.json), parses them, applies the extended
# eligibility rule and MERGES the new schools into faculty_candidates.csv and
# faculty_raw.csv. Rows of schools outside ITERATION2_CONTINUED_SCHOOLS are never changed, and
# re-running replaces only the iteration-3 schools' rows (idempotent).
# Pages that cannot be fetched by script (JavaScript apps, HTTP 403) are saved from a
# normal browser as tmp/iteration2_continued/sources/<key>.html plus <key>.meta.json and are not
# overridden here; no CAPTCHA or access-control bypass is attempted.
# Usage: ruby script/data/prepare_iteration2_continued.rb [--offline]
require 'net/http'
require 'digest'
require 'time'
require_relative 'prepare_public'
require_relative 'lib/iteration2_continued_rosters'

module NicheRank
  module Iteration2Continued
    SOURCE_DIR = File.join(PublicPreparation::ROOT, 'tmp/iteration2_continued/sources')
    UA = 'NicheRank-course-data/0.1 public faculty directory research'

    def self.fetch(key, source, directory)
      path = File.join(directory, "#{key}.html")
      return :cached if File.exist?(path)
      uri = URI(source.fetch('url'))
      6.times do |hop|
        raise 'Public sources must use HTTPS without credentials' unless uri.scheme == 'https' && uri.userinfo.nil?
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 45) { |h| h.get(uri.request_uri, 'User-Agent' => UA) }
        if response.is_a?(Net::HTTPRedirection)
          raise 'Too many redirects' if hop == 5
          uri = URI.join(uri, response.fetch('location'))
          next
        end
        raise "HTTP #{response.code}; save it from a normal browser instead (no access-control bypass)" unless response.is_a?(Net::HTTPSuccess)
        body = response.body.force_encoding('UTF-8').scrub
        File.write("#{path}.tmp", body)
        File.rename("#{path}.tmp", path)
        NicheRank.atomic_json(path.sub(/\.html\z/, '.meta.json'), { 'url' => source['url'], 'final_url' => uri.to_s, 'retrieved_at' => Time.now.utc.iso8601,
                                                                    'status' => response.code.to_i, 'sha256' => Digest::SHA256.hexdigest(body) })
        return :fetched
      end
    end

    def self.merge(existing, fresh, schools)
      kept = existing.reject { |r| schools.include?(r['university']) }
      (kept + fresh).sort_by { |r| [r['university'], NicheRank.normalize(r['name'])] }
    end

    def self.run(offline: false, source_dir: SOURCE_DIR, manual: File.join(PublicPreparation::ROOT, 'db/data/manual'))
      FileUtils.mkdir_p(source_dir)
      sources = JSON.parse(File.read(File.join(manual, 'iteration2_continued_sources.json')))
      problems = {}
      sources.each do |key, source|
        if source['method'] == 'browser'
          path = File.join(source_dir, "#{key}.html")
          if File.exist?(path) && !File.exist?(path.sub(/\.html\z/, '.meta.json'))
            body = File.read(path)
            NicheRank.atomic_json(path.sub(/\.html\z/, '.meta.json'), { 'url' => source['url'], 'final_url' => source['url'], 'retrieved_at' => File.mtime(path).utc.iso8601,
                                                                        'status' => 'saved from a normal browser', 'sha256' => Digest::SHA256.hexdigest(body) })
          end
          problems[key] = 'browser snapshot missing (save the page from a normal browser)' unless File.exist?(path)
          next
        end
        next if offline
        begin
          fetch(key, source, source_dir)
        rescue StandardError => e
          problems[key] = e.message
        end
      end
      prep = PublicPreparation.new(source_dir: source_dir, manual: manual)
      prep.iteration2_continued
      rows = prep.candidates.group_by { |r| [r['university'], NicheRank.normalize(r['name'])] }.values.map do |group|
        row = group.first.dup
        row['unit'] = group.map { |r| r['unit'] }.uniq.join('; ')
        row['source_url'] = group.map { |r| r['source_url'] }.uniq.join('; ')
        # A parser may already have decided (e.g. a directory section such as Adjunct Faculty).
        row['eligibility_status'], row['eligibility_reason'] = PublicPreparation.classify_extended(row['title']) if row['eligibility_status'].to_s.empty?
        row
      end
# Where the official directory gives no link, use the reviewed CSRankings homepage (build_homepage_fallbacks.rb).
fallbacks_path = File.join(manual, 'iteration2_continued_homepage_fallbacks.csv')
fallbacks = File.exist?(fallbacks_path) ? NicheRank.read_csv(fallbacks_path).to_h { |r| [[r['university'], r['name']], r['homepage_url']] } : {}
rows.each do |r|
  fallback = fallbacks[[r['university'], r['name']]]
  r['homepage_url'] = fallback if r['homepage_url'].to_s.strip.empty? && fallback
end
      schools = PublicPreparation::ITERATION2_CONTINUED_SCHOOLS
      headers = PublicPreparation::ROSTER_HEADERS + PublicPreparation::EXTRA
      candidates_path = File.join(manual, 'faculty_candidates.csv')
      raw_path = File.join(manual, 'faculty_raw.csv')
      merged = merge(NicheRank.read_csv(candidates_path), rows, schools)
      NicheRank.write_csv(candidates_path, headers, merged)
      raw = merge(NicheRank.read_csv(raw_path), rows.select { |r| r['eligibility_status'] == 'included' }, schools)
      NicheRank.write_csv(raw_path, PublicPreparation::ROSTER_HEADERS, raw)
      counts = rows.group_by { |r| r['university'] }.transform_values { |g| g.group_by { |r| r['eligibility_status'] }.transform_values(&:size) }
      NicheRank.atomic_json(File.join(manual, 'iteration2_continued_roster_counts.json'), counts)
      { 'counts' => counts, 'fetch_problems' => problems, 'sources_without_snapshot' => sources.keys.reject { |k| File.exist?(File.join(source_dir, "#{k}.html")) } }
    end
  end
end

puts JSON.pretty_generate(NicheRank::Iteration2Continued.run(offline: ARGV.include?('--offline'))) if $PROGRAM_NAME == __FILE__
