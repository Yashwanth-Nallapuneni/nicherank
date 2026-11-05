#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require_relative 'lib/nicherank'

module NicheRank
  class Runner
    ROOT = File.expand_path('../..', __dir__)
    def initialize(options)
      @options = options
      @manual = File.join(ROOT, 'db/data/manual')
      @client = Client.new(cache: options[:cache], offline: options[:offline], max_requests: options[:max_requests])
    end

    def table(name)
      NicheRank.read_csv(File.join(@manual, "#{name}.csv"))
    end

    def run(command)
      case command
      when 'institutions'
        rows = table('universities').flat_map do |u|
          @client.get('institutions', 'search' => u['name'], 'filter' => 'country_code:US', 'per_page' => 5).fetch('results').map do |i|
            { 'requested_name' => u['name'], 'candidate_id' => NicheRank.short_id(i['id'], 'I'), 'candidate_name' => i['display_name'],
              'city' => i.dig('geo', 'city'), 'state' => i.dig('geo', 'region'), 'country_code' => i['country_code'], 'ror' => i['ror'] }
          end
        end
        write_output('institution_candidates', %w[requested_name candidate_id candidate_name city state country_code ror], rows)
      when 'candidates'
        universities = table('universities').to_h { |u| [u['name'], u] }
        rows = []
        people = table('faculty_raw')
        completed = 0
        begin
          people.each do |person|
            institution = NicheRank.short_id(universities.fetch(person['university']).fetch('openalex_id'), 'I')
            constrained = @client.get('authors', 'search' => person['name'], 'filter' => "affiliations.institution.id:#{institution}", 'per_page' => 10).fetch('results')
            # Always search without institution too: alias review requires looking beyond
            # current institutional metadata. Results are suggestions, never approvals.
            wide = @client.get('authors', 'search' => person['name'], 'per_page' => 10).fetch('results')
            (constrained + wide).uniq { |a| a['id'] }.each do |a|
              rows << { 'university' => person['university'], 'name' => person['name'], 'candidate_id' => NicheRank.short_id(a['id'], 'A'),
                'candidate_name' => a['display_name'], 'orcid' => a['orcid'], 'works_count' => a['works_count'],
                'institutions' => Array(a['last_known_institutions']).map { |i| i['display_name'] }.join('; '),
                'institution_search_hit' => constrained.any? { |x| x['id'] == a['id'] }, 'status' => 'needs_review' }
            end
            completed += 1
          end
        ensure
          # A request-cap or API error still leaves completed suggestions available
          # for review. Source caches resume the next run without repeat downloads.
          write_output('author_candidates', %w[university name candidate_id candidate_name orcid works_count institutions institution_search_hit status], rows)
          NicheRank.atomic_json(File.join(@options[:output], 'candidate_progress.json'), { 'completed_roster_entries' => completed,
                               'total_roster_entries' => people.size, 'complete' => completed == people.size })
        end
      when 'collect'
        collect
      when 'export'
        snapshot = JSON.parse(File.read(@options[:snapshot]))
        export(snapshot)
      when 'validate'
        errors = Validator.new(@options[:output]).errors
        raise errors.join("\n") unless errors.empty?
        puts 'CSV validation passed.'
      else
        raise 'Unknown command. Use --help.'
      end
    end

    def write_output(name, headers, rows)
      path = File.join(@options[:output], "#{name}.csv")
      NicheRank.write_csv(path, headers, rows)
      puts "Wrote #{rows.size} rows to #{path}"
    end

    def collect
      universities = table('universities')
      matches = table('author_matches').select { |m| m['status'] == 'verified' }
      matches = matches.first(@options[:limit]) if @options[:limit]
      raise 'No verified author matches. Review candidates and fill author_matches.csv first.' if matches.empty?
      raise 'Verified matches require evidence and an alias review date' if matches.any? { |m| m['evidence_url'].to_s.empty? || m['alias_checked_on'].to_s.empty? }
      raise 'Duplicate canonical author in match file' unless matches.map { |m| m['openalex_id'] }.uniq.size == matches.size
      roster = table('faculty_raw')
      relevant = matches.map { |m| m['university'] }.uniq
      universities = universities.select { |u| relevant.include?(u['name']) }
      universities.each { |u| NicheRank.short_id(u['openalex_id'], 'I') }
      lookup = universities.to_h { |u| [u['name'], u] }
      aliases = table('author_aliases').select { |a| matches.any? { |m| m['openalex_id'] == a['professor_openalex_id'] } }
      professors = matches.map do |m|
        person = roster.find { |r| r['university'] == m['university'] && r['name'] == m['name'] }
        raise "No faculty roster entry for #{m['name']}" unless person
        canonical = NicheRank.short_id(m['openalex_id'], 'A')
        ids = [canonical] + aliases.select { |a| a['professor_openalex_id'] == canonical }.map { |a| NicheRank.short_id(a['alias_openalex_id'], 'A') }
        author = @client.get("authors/#{canonical}")
        first_year = ids.filter_map do |id|
          # Earliest record over ALL years; this is not restricted to 2015+.
          earliest = @client.get('works', 'filter' => "authorships.author.id:#{id}", 'sort' => 'publication_date:asc', 'per_page' => 1, 'select' => 'id,publication_year').fetch('results').first
          earliest && earliest['publication_year']
        end.min
        { 'openalex_id' => canonical, 'name' => person['name'], 'university_openalex_id' => lookup.fetch(m['university'])['openalex_id'],
          'title' => person['title'], 'homepage_url' => person['homepage_url'], 'orcid' => author['orcid'], 'first_pub_year' => first_year,
          'works_count' => author['works_count'], 'h_index' => author.dig('summary_stats', 'h_index'), 'match_confidence' => m['match_confidence'] }
      end
      ids = (professors.map { |p| p['openalex_id'] } + aliases.map { |a| a['alias_openalex_id'] }).uniq.sort
      works = []
      ids.each_slice(50).with_index do |batch, index|
        $stderr.puts "Collecting author batch #{index + 1}; #{@client.requests} live requests this run"
        @client.each_page('works', 'filter' => "authorships.author.id:#{batch.join('|')},from_publication_date:2015-01-01,to_publication_date:#{@options[:cutoff]},is_retracted:false,type:#{SOURCE_TYPES.join('|')}") do |page|
          works.concat(page)
        end
        # Raw pages are cached atomically, so a crash inside a batch also resumes.
        NicheRank.atomic_json(File.join(@options[:cache], 'progress.json'), { 'completed_batch' => index + 1, 'author_ids' => ids, 'cutoff' => @options[:cutoff] })
      end
      snapshot = { 'universities' => universities, 'professors' => professors, 'aliases' => aliases, 'works' => works.uniq { |w| w['id'] },
                   'cutoff' => @options[:cutoff], 'scope' => @options[:limit] ? 'sample' : 'verified_roster_subset',
                   'source_reads' => @client.source_reads, 'live_requests_this_run' => @client.requests }
      NicheRank.atomic_json(@options[:snapshot], snapshot)
      export(snapshot)
    end

    def export(snapshot)
      exporter = Exporter.new(universities: snapshot.fetch('universities'), professors: snapshot.fetch('professors'), aliases: snapshot.fetch('aliases'),
                              works: snapshot.fetch('works'), tiers: table('venue_tiers'), cutoff: snapshot.fetch('cutoff'))
      manifest = exporter.export(@options[:output], scope: snapshot.fetch('scope'), extra_review: table('review'))
      # Hashes bind the export to the exact reviewed inputs and raw snapshot.
      manifest['snapshot_sha256'] = Digest::SHA256.file(@options[:snapshot]).hexdigest
      manifest['manual_input_sha256'] = Dir[File.join(@manual, '*.csv')].sort.to_h { |p| [File.basename(p), Digest::SHA256.file(p).hexdigest] }
      manifest['sources'] = ['https://api.openalex.org', *table('faculty_raw').map { |p| p['source_url'] }, *table('venue_tiers').map { |r| r['source'] }].compact.uniq
      manifest['source_reads'] = snapshot.fetch('source_reads', {})
      manifest['complete_ten_school_dataset'] = false
      manifest['faculty_roster_scope'] = 'Incomplete until all ten school directories and eligibility decisions have been reviewed.'
      NicheRank.atomic_json(File.join(@options[:output], 'manifest.json'), manifest)
      puts JSON.pretty_generate(manifest['counts'])
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = NicheRank::Runner::ROOT
  options = { cache: ENV.fetch('OPENALEX_CACHE_DIR', File.join(root, 'tmp/openalex_cache')), offline: false, max_requests: 1000,
              output: File.join(root, 'data/output'), snapshot: File.join(root, 'tmp/snapshot.json'), cutoff: Date.today.iso8601 }
  parser = OptionParser.new do |o|
    o.banner = "ruby script/data/collect.rb COMMAND [options]\nCommands: institutions, candidates, collect, export, validate"
    o.on('--offline', 'Only read cached API responses; never use network') { options[:offline] = true }
    o.on('--cache PATH') { |v| options[:cache] = File.expand_path(v) }
    o.on('--output PATH') { |v| options[:output] = File.expand_path(v) }
    o.on('--snapshot PATH') { |v| options[:snapshot] = File.expand_path(v) }
    o.on('--cutoff YYYY-MM-DD') { |v| options[:cutoff] = Date.iso8601(v).iso8601 }
    o.on('--limit N', Integer, 'Collect only the first N verified professors for a sample') { |v| raise OptionParser::InvalidArgument, 'limit must be positive' unless v.positive?; options[:limit] = v }
    o.on('--max-requests N', Integer, 'Hard cap on live requests this run; cached reads are free') { |v| raise OptionParser::InvalidArgument, 'request limit must be positive' unless v.positive?; options[:max_requests] = v }
    o.on('-h', '--help') { puts o; exit }
  end
  begin
    parser.parse!
    NicheRank.load_openalex_key(File.join(root, '.env.local'))
    command = ARGV.shift
    raise OptionParser::InvalidArgument, 'Provide exactly one command; use --help' unless command && ARGV.empty?
    NicheRank::Runner.new(options).run(command)
  rescue StandardError => e
    # Do not print HTTP request objects, credential-bearing URLs, or raw bodies.
    warn "#{e.class}: #{e.message}"
    exit 1
  end
end
