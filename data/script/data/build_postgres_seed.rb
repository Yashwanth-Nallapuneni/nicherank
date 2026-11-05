#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate parameter-free, escaped SQL from the already validated real sample.
# No credentials, network, database or Rails needed to generate the seed.
require_relative 'lib/nicherank'

module NicheRank
  module PostgresSeed
    def self.literal(value)
      return 'NULL' if value.nil? || value == ''
      raise ArgumentError, 'Postgres text cannot contain NUL' if value.to_s.include?("\0")
      "'#{value.to_s.gsub("'", "''")}'"
    end

    def self.reference(table, id)
      raise ArgumentError, 'Invalid reference table' unless %w[universities professors papers].include?(table)
      "(SELECT id FROM public.#{table} WHERE openalex_id = #{literal(id)})"
    end

    def self.upsert(table, row, conflict, expressions = {})
      allowed = %w[universities professors papers authorships author_aliases paper_duplicates data_review_cases dataset_metadata]
      raise ArgumentError, 'Invalid destination table' unless allowed.include?(table)
      columns = row.keys
      values = columns.map { |key| expressions.fetch(key) { literal(row[key]) } }
      updates = (columns - conflict).map { |key| "#{key} = EXCLUDED.#{key}" }.join(', ')
      "INSERT INTO public.#{table} (#{columns.join(', ')}) VALUES (#{values.join(', ')}) ON CONFLICT (#{conflict.join(', ')}) DO UPDATE SET #{updates};"
    end

    def self.build(root)
      directory = File.join(root, 'db/data/sample')
      errors = Validator.new(directory).errors
      raise errors.join('; ') unless errors.empty?
      statements = File.read(File.join(root, 'db/postgres/schema.sql')).split(/;\s*(?:\n|\z)/).map(&:strip).reject(&:empty?).map { |s| s + ';' }
      HEADERS.keys.each do |name|
        NicheRank.read_csv(File.join(directory, "#{name}.csv")).each do |input|
          row = input.dup
          case name
          when 'universities'
            statements << upsert(name, row, ['openalex_id'])
          when 'papers'
            row['paper_type'] = row.delete('type')
            row['paper_type'] = 'conference-paper' if row['paper_type'] == 'proceedings-article'
            mappings = NicheRank.read_csv(File.join(root, 'db/data/manual/venue_tiers.csv'))
            mapping = mappings.find { |m| NicheRank.normalize(m['venue']) == NicheRank.normalize(row['venue']) }
            row['venue_tier_source'] = mapping && (mapping['kind'] == 'journal_custom' ? 'custom' : 'core2023')
            statements << upsert(name, row, ['openalex_id'])
          when 'professors'
            institution = row.delete('university_openalex_id')
            row['university_id'] = institution
            statements << upsert(name, row, ['openalex_id'], 'university_id' => reference('universities', institution))
          when 'authorships'
            professor, paper = row.delete('professor_openalex_id'), row.delete('paper_openalex_id')
            row['professor_id'], row['paper_id'] = professor, paper
            statements << upsert(name, row, %w[professor_id paper_id], 'professor_id' => reference('professors', professor), 'paper_id' => reference('papers', paper))
          when 'author_aliases'
            professor = row.delete('professor_openalex_id')
            row['professor_id'] = professor
            statements << upsert(name, row, ['alias_openalex_id'], 'professor_id' => reference('professors', professor))
          when 'duplicates'
            paper = row.delete('retained_openalex_id')
            row['retained_paper_id'] = paper
            statements << upsert('paper_duplicates', row, ['discarded_openalex_id'], 'retained_paper_id' => reference('papers', paper))
          when 'review'
            row['fingerprint'] = Digest::SHA256.hexdigest(JSON.generate(input))
            statements << upsert('data_review_cases', row, ['fingerprint'])
          end
        end
      end
      manifest = JSON.parse(File.read(File.join(directory, 'manifest.json')))
      statements << upsert('dataset_metadata', { 'dataset_key' => 'sample-2026-11-04', 'manifest' => JSON.generate(manifest) }, ['dataset_key'])
      output = File.join(root, 'db/postgres')
      NicheRank.atomic_json(File.join(output, 'sample_statements.json'), statements)
      File.write(File.join(output, 'sample.sql'), "BEGIN;\nSET LOCAL standard_conforming_strings = on;\n" + statements.join("\n") + "\nCOMMIT;\n")
      puts "Generated #{statements.size} statements from the real, validated sample. No database connection used."
    end
  end
end

NicheRank::PostgresSeed.build(File.expand_path('../..', __dir__)) if $PROGRAM_NAME == __FILE__
