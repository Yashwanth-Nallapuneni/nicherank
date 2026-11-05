#!/usr/bin/env ruby
# frozen_string_literal: true

# Transactional, idempotent COPY staging loader. Schema changes are separate.
require 'pg'
require_relative 'lib/nicherank'

module NicheRank
  class PostgresLoader
    TABLES = {
      'universities' => ['universities', %w[openalex_id]],
      'professors' => ['professors', %w[openalex_id]],
      'papers' => ['papers', %w[openalex_id]],
      'authorships' => ['authorships', %w[professor_id paper_id]],
      'author_aliases' => ['author_aliases', %w[alias_openalex_id]],
      'duplicates' => ['paper_duplicates', %w[discarded_openalex_id]],
      'review' => ['data_review_cases', %w[fingerprint]]
    }.freeze
    CASTS = { 'first_pub_year' => 'integer', 'works_count' => 'integer', 'h_index' => 'integer', 'year' => 'integer',
              'citations' => 'integer', 'is_open_access' => 'boolean', 'is_corresponding' => 'boolean' }.freeze

    def initialize(connection, directory, root: File.expand_path('../..', __dir__))
      @db, @directory = connection, directory
      @tiers = NicheRank.read_csv(File.join(root, 'db/data/manual/venue_tiers.csv')).to_h { |r| [NicheRank.normalize(r['venue']), r] }
    end

    def transform(name, input)
      row = input.transform_values { |value| value == '' ? nil : value }
      if name == 'papers'
        row['paper_type'] = row.delete('type')
        row['paper_type'] = 'conference-paper' if row['paper_type'] == 'proceedings-article'
        mapping = @tiers[NicheRank.normalize(row['venue'])]
        row['venue_tier_source'] = row['venue_tier'] && mapping && (mapping['kind'] == 'journal_custom' ? 'custom' : 'core2023')
        raise 'A ranked venue requires provenance' if row['venue_tier'] && !row['venue_tier_source']
      elsif name == 'review'
        row['fingerprint'] = Digest::SHA256.hexdigest(JSON.generate(input))
      end
      row
    end

    def load
      manifest = JSON.parse(File.read(File.join(@directory, 'manifest.json')))
      errors = Validator.new(@directory, allow_empty_professors: manifest['keep_empty_professors'] == true).errors
      raise errors.join('; ') unless errors.empty?
      @db.transaction do
        @db.exec("SET LOCAL lock_timeout = '15s'")
        TABLES.each do |name, (destination, conflict)|
          csv = CSV.open(File.join(@directory, "#{name}.csv"), headers: true)
          first = csv.shift
          next unless first
          row = transform(name, first.to_h)
          headers = row.keys
          stage = "stage_#{name}"
          @db.exec("CREATE TEMP TABLE #{stage} (#{headers.map { |h| "#{h} text" }.join(',')}) ON COMMIT DROP")
          @db.copy_data("COPY #{stage} (#{headers.join(',')}) FROM STDIN WITH (FORMAT csv)") do
            @db.put_copy_data(CSV.generate_line(headers.map { |h| row[h] }))
            csv.each do |record|
              values = transform(name, record.to_h)
              @db.put_copy_data(CSV.generate_line(headers.map { |h| values[h] }))
            end
          end
          csv.close
          columns, expressions, joins = [], [], []
          headers.each do |header|
            target, expression = header, "s.#{header}"
            case header
            when 'university_openalex_id'
              target, expression = 'university_id', 'u.id'
              joins << 'JOIN public.universities u ON u.openalex_id=s.university_openalex_id'
            when 'professor_openalex_id'
              target, expression = 'professor_id', 'p.id'
              joins << 'JOIN public.professors p ON p.openalex_id=s.professor_openalex_id'
            when 'paper_openalex_id', 'retained_openalex_id'
              target, expression = header == 'paper_openalex_id' ? 'paper_id' : 'retained_paper_id', 'w.id'
              joins << "JOIN public.papers w ON w.openalex_id=s.#{header}"
            else
              expression += "::#{CASTS[header]}" if CASTS.key?(header)
            end
            columns << target
            expressions << expression
          end
          updates = (columns - conflict).map { |c| "#{c}=EXCLUDED.#{c}" }
          updates << 'updated_at=now()' if %w[universities professors papers authorships author_aliases].include?(destination)
          sql = "INSERT INTO public.#{destination} (#{columns.join(',')}) SELECT #{expressions.join(',')} FROM #{stage} s #{joins.join(' ')} WHERE true ON CONFLICT (#{conflict.join(',')}) DO UPDATE SET #{updates.join(',')}"
          result = @db.exec(sql)
          expected = @db.exec("SELECT count(*) FROM #{stage}").first.fetch('count').to_i
          raise "Missing references while loading #{name}" unless result.cmd_tuples == expected
          puts "#{destination}: #{result.cmd_tuples} rows loaded"
        end
        key = "#{manifest.fetch('scope')}-#{manifest.fetch('collection_cutoff')}"
        @db.exec_params('INSERT INTO public.dataset_metadata(dataset_key,manifest) VALUES($1,$2::jsonb) ON CONFLICT(dataset_key) DO UPDATE SET manifest=EXCLUDED.manifest,loaded_at=now()', [key, JSON.generate(manifest.merge('database_schema_version' => 2))])
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    directory = File.expand_path(ARGV.fetch(0))
    credential_file = ARGV[1]
    url = credential_file ? File.readlines(credential_file, chomp: true).find { |l| l.start_with?('DATABASE_URL=') }&.split('=', 2)&.last : ENV['DATABASE_URL']
    raise 'Provide a private credential file or DATABASE_URL' if url.to_s.empty?
    db = PG.connect(url)
    NicheRank::PostgresLoader.new(db, directory).load
  rescue StandardError => e
    # libpq error messages can include connection details; never print them.
    warn "Database load failed (#{e.class}); transaction rolled back. Inspect privately."
    exit 1
  ensure
    db&.close
  end
end
