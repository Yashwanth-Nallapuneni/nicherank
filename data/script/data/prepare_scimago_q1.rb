#!/usr/bin/env ruby
# frozen_string_literal: true

# Extracts Computer-Science Q1 journals from a SCImago Journal & Country Rank
# export (downloaded manually in a browser; the site blocks scripts). Only the
# Q1 list is committed, never the full SCImago file.
#
# SCImago's "SJR Best Quartile" is the best quartile across ALL of a journal's
# categories, so a biomedical journal can be "Q1" through a non-CS category.
# A journal is kept only when Q1 is reached in at least one CS subject category.
require 'digest'
require 'time'
require_relative 'lib/nicherank'

module NicheRank
  module ScimagoPreparation
    SOURCE_URL = 'https://www.scimagojr.com/journalrank.php?area=1700&type=j'
    CS_CATEGORIES = ['Artificial Intelligence', 'Computational Theory and Mathematics', 'Computer Graphics and Computer-Aided Design',
                     'Computer Networks and Communications', 'Computer Science (miscellaneous)', 'Computer Science Applications',
                     'Computer Vision and Pattern Recognition', 'Hardware and Architecture', 'Human-Computer Interaction',
                     'Information Systems', 'Signal Processing', 'Software'].freeze
    HEADERS = %w[sourceid title issns ranking cs_q1_categories best_quartile year source_url].freeze

    def self.issn(raw)
      digits = raw.to_s.strip.upcase.delete('-')
      digits.match?(/\A\d{7}[\dX]\z/) ? "#{digits[0, 4]}-#{digits[4, 4]}" : nil
    end

    def self.parse_categories(text)
      text.to_s.split(/;\s*/).filter_map do |part|
        m = part.strip.match(/\A(.+?)\s*\((Q[1-4])\)\z/)
        [m[1], m[2]] if m
      end
    end

    def self.extract(input, year)
      table = CSV.read(input, col_sep: ';', headers: true, encoding: 'bom|utf-8', liberal_parsing: true)
      required = %w[Sourceid Title Type Issn Categories]
      raise 'Unexpected SCImago CSV structure' unless (required - table.headers).empty?
      rows = table.select { |r| r['Type'] == 'journal' }.filter_map do |r|
        q1 = parse_categories(r['Categories']).select { |name, q| q == 'Q1' && CS_CATEGORIES.include?(name) }.map(&:first)
        next if q1.empty?
        issns = r['Issn'].to_s.split(',').filter_map { |value| issn(value) }.uniq
        { 'sourceid' => r['Sourceid'].to_s.strip, 'title' => r['Title'].to_s.strip, 'issns' => issns.join(';'), 'ranking' => 'Q1',
          'cs_q1_categories' => q1.join('; '), 'best_quartile' => r['SJR Best Quartile'], 'year' => year.to_s, 'source_url' => SOURCE_URL }
      end
      [rows, table.size]
    end

    def self.prepare(input, directory, year: 2025)
      rows, total = extract(input, year)
      NicheRank.write_csv(File.join(directory, 'scimago_cs_q1.csv'), HEADERS, rows)
      summary = { 'url' => SOURCE_URL, 'edition' => "SCImago #{year} (Subject Area: Computer Science)", 'file_modified' => File.mtime(input).utc.iso8601,
                  'sha256' => Digest::SHA256.file(input).hexdigest, 'journals_in_file' => total, 'cs_q1_journals' => rows.size,
                  'without_issn' => rows.count { |r| r['issns'].empty? },
                  'dropped_best_quartile_q1_not_in_cs' => table_best_q1(input) - rows.size,
                  'note' => 'Only journals with Q1 in a CS subject category are kept; the full SCImago file is not committed.' }
      NicheRank.atomic_json(File.join(directory, 'scimago_sources.json'), summary)
      summary
    end

    def self.table_best_q1(input)
      CSV.read(input, col_sep: ';', headers: true, encoding: 'bom|utf-8', liberal_parsing: true).count { |r| r['SJR Best Quartile'] == 'Q1' }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  puts JSON.pretty_generate(NicheRank::ScimagoPreparation.prepare(ARGV[0] || File.join(root, 'tmp/public_sources/scimagojr_2025_computer_science.csv'),
                                                                  ARGV[1] || File.join(root, 'db/data/manual')))
end
