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

    def initialize(connection, directory, root: File.expand_path('../..', __dir__), reconcile: false)
      @db, @directory = connection, directory
      @root, @reconcile = root, reconcile
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
      raise 'Reconciliation requires an audited revision-2 manifest' if @reconcile && manifest['audit_revision'] != 2
      errors = Validator.new(@directory, allow_empty_professors: manifest['keep_empty_professors'] == true).errors
      raise errors.join('; ') unless errors.empty?
      @db.transaction do
        @db.exec("SET LOCAL lock_timeout = '15s'")
        @db.exec("SELECT pg_advisory_xact_lock(hashtext('nicherank-data-load'))")
        if @reconcile
          NicheRank.read_csv(File.join(@root, 'db/data/manual/identity_corrections.csv')).each do |correction|
            old_id, new_id = correction.values_at('old_openalex_id', 'new_openalex_id')
            rows = @db.exec_params('SELECT openalex_id FROM public.professors WHERE openalex_id IN ($1,$2) FOR UPDATE', [old_id, new_id]).map { |r| r['openalex_id'] }
            raise 'Both old and new canonical professors exist; explicit merge required' if rows.include?(old_id) && rows.include?(new_id)
            @db.exec_params('UPDATE public.professors SET openalex_id=$1,updated_at=now() WHERE openalex_id=$2', [new_id, old_id]) if rows.include?(old_id)
          end
        end
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
          expected = @db.exec("SELECT count(*) FROM #{stage}").first.fetch('count').to_i
          referenced = @db.exec("SELECT count(*) FROM #{stage} s #{joins.join(' ')}").first.fetch('count').to_i
          raise "Missing references while loading #{name}" unless referenced == expected
          # Avoid rewriting unchanged papers/GIN entries on repeat loads.
          mutable = columns - conflict
          changed = "(#{mutable.map { |c| "#{destination}.#{c}" }.join(',')}) IS DISTINCT FROM (#{mutable.map { |c| "EXCLUDED.#{c}" }.join(',')})"
          sql = "INSERT INTO public.#{destination} (#{columns.join(',')}) SELECT #{expressions.join(',')} FROM #{stage} s #{joins.join(' ')} WHERE true ON CONFLICT (#{conflict.join(',')}) DO UPDATE SET #{updates.join(',')} WHERE #{changed}"
          result = @db.exec(sql)
          puts "#{destination}: #{expected} staged; #{result.cmd_tuples} inserted/changed"
          $stdout.flush
        end
        if @reconcile
          # These are derived data-team tables. Keep numeric professor IDs stable,
          # remove superseded derived links only for the staged ten-school roster,
          # and preserve unrelated professors and the review history.
          @db.exec('DELETE FROM public.author_aliases a USING public.professors p,stage_professors s WHERE a.professor_id=p.id AND p.openalex_id=s.openalex_id AND NOT EXISTS(SELECT 1 FROM stage_author_aliases x WHERE x.professor_openalex_id=p.openalex_id AND x.alias_openalex_id=a.alias_openalex_id)')
          @db.exec('DELETE FROM public.paper_duplicates d WHERE NOT EXISTS(SELECT 1 FROM stage_duplicates s WHERE s.discarded_openalex_id=d.discarded_openalex_id) AND EXISTS(SELECT 1 FROM public.papers w JOIN public.authorships a ON a.paper_id=w.id JOIN public.professors p ON p.id=a.professor_id JOIN stage_professors s ON s.openalex_id=p.openalex_id WHERE w.id=d.retained_paper_id)')
          @db.exec('DELETE FROM public.authorships a USING public.professors p,stage_professors s WHERE a.professor_id=p.id AND p.openalex_id=s.openalex_id AND NOT EXISTS(SELECT 1 FROM stage_authorships x JOIN public.papers w ON w.openalex_id=x.paper_openalex_id WHERE x.professor_openalex_id=p.openalex_id AND w.id=a.paper_id)')
          @db.exec('DELETE FROM public.papers w WHERE NOT EXISTS(SELECT 1 FROM stage_papers s WHERE s.openalex_id=w.openalex_id) AND NOT EXISTS(SELECT 1 FROM public.authorships a WHERE a.paper_id=w.id) AND NOT EXISTS(SELECT 1 FROM public.paper_duplicates d WHERE d.retained_paper_id=w.id)')
          @db.exec("UPDATE public.data_review_cases r SET status='superseded',resolution='Superseded by audited revision 2; retained as historical provenance' WHERE NOT EXISTS(SELECT 1 FROM stage_review s WHERE s.fingerprint=r.fingerprint)")
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
    NicheRank::PostgresLoader.new(db, directory, reconcile: ARGV.include?('--reconcile')).load
  rescue StandardError => e
    # libpq error messages can include connection details; never print them.
    warn "Database load failed (#{e.class}); transaction rolled back. Inspect privately."
    # Private local diagnostics help debug failed transactions without printing a
    # connection URL or driver exception into chat/tool output.
    if defined?(directory) && directory
      FileUtils.mkdir_p(File.join(File.dirname(directory), 'load_diagnostics'))
      path = File.join(File.dirname(directory), 'load_diagnostics/last_error.txt')
      File.write(path, "#{e.class}\n#{e.message}\n")
      File.chmod(0o600, path)
    end
    exit 1
  ensure
    db&.close
  end
end
