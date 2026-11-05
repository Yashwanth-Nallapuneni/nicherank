# frozen_string_literal: true

require 'csv'
require 'json'
require 'net/http'
require 'uri'
require 'digest'
require 'fileutils'
require 'date'
require 'time'
require 'set'

module NicheRank
  HEADERS = {
    'universities' => %w[openalex_id name short_name city state cs_dept_url],
    'professors' => %w[openalex_id name university_openalex_id title homepage_url orcid first_pub_year works_count h_index match_confidence],
    'papers' => %w[openalex_id title abstract year type venue venue_tier citations doi primary_topic field keywords is_open_access oa_url language],
    'authorships' => %w[professor_openalex_id paper_openalex_id position is_corresponding],
    'author_aliases' => %w[professor_openalex_id alias_openalex_id],
    'duplicates' => %w[discarded_openalex_id retained_openalex_id reason],
    'review' => %w[issue_type university name_or_venue candidate_ids reason status resolution]
  }.freeze
  TYPES = %w[article proceedings-article preprint book-chapter].freeze
  SOURCE_TYPES = %w[article conference-paper preprint book-chapter].freeze
  TYPE_MAPPING = { 'conference-paper' => 'proceedings-article' }.freeze
  TIERS = ['A*', 'A', 'B', 'C'].freeze
  GENERIC_TITLES = ['introduction', 'editorial', 'preface', 'foreword', 'demo', 'demonstration',
                    'acknowledgments', 'acknowledgements', 'contents', 'table of contents',
                    'abstract', 'abstracts', 'index', 'book review', 'reviews', 'correction',
                    'erratum', 'the presidents page', 'einführung', 'invited article foreword'].freeze

  def self.short_id(value, kind)
    id = value.to_s.sub(%r{\Ahttps?://openalex\.org/}i, '')
    raise ArgumentError, "Invalid #{kind} identifier" unless id.match?(/\A#{kind}\d+\z/)
    id
  end

  def self.normalize(text)
    text.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^\p{L}\p{N}\s]/, '').gsub(/\s+/, ' ').strip
  end

  def self.doi(value)
    value.to_s.strip.downcase.sub(%r{\Ahttps?://(?:dx\.)?doi\.org/}, '').sub(/\Adoi:\s*/, '')
  end

  def self.preprint_record?(work)
    work['type'] == 'preprint' || doi(work['doi']).match?(%r{\A(?:10\.48550/arxiv\.|10\.1101/|10\.2139/ssrn\.)}i)
  end

  def self.abstract(index)
    return nil unless index.is_a?(Hash) && !index.empty?
    positions = {}
    index.each do |word, indexes|
      Array(indexes).each do |position|
        raise ArgumentError, 'Malformed abstract position' unless position.is_a?(Integer) && position.between?(0, 100_000)
        raise ArgumentError, 'Conflicting abstract positions' if positions.key?(position) && positions[position] != word
        positions[position] = word
      end
    end
    positions.sort.map(&:last).join(' ')
  end

  def self.read_csv(path)
    CSV.read(path, headers: true, encoding: 'bom|utf-8').map(&:to_h)
  end

  def self.write_csv(path, headers, rows)
    FileUtils.mkdir_p(File.dirname(path))
    temporary = "#{path}.tmp"
    CSV.open(temporary, 'w', encoding: 'utf-8', write_headers: true, headers: headers) do |csv|
      rows.each { |row| csv << headers.map { |key| row[key] } }
    end
    File.rename(temporary, path)
  end

  def self.atomic_json(path, object)
    FileUtils.mkdir_p(File.dirname(path))
    File.write("#{path}.tmp", JSON.pretty_generate(object) + "\n")
    File.rename("#{path}.tmp", path)
  end

  # Read only the one supported secret, without executing shell code or logging it.
  def self.load_openalex_key(path)
    return unless ENV['OPENALEX_API_KEY'].to_s.empty? && File.file?(path)
    lines = File.readlines(path, chomp: true).reject { |line| line.strip.empty? || line.lstrip.start_with?('#') }
    line = lines.find { |value| value.start_with?('OPENALEX_API_KEY=') }
    return unless line
    value = line.split('=', 2).last.strip
    value = value[1...-1] if value.size >= 2 && ((value.start_with?('"') && value.end_with?('"')) || (value.start_with?("'") && value.end_with?("'")))
    raise ArgumentError, 'Invalid OpenAlex key format; do not include shell commands' if value.match?(/[\r\n\s`$]/)
    ENV['OPENALEX_API_KEY'] = value unless value.empty?
  end

  # Cache keys and stored metadata never contain the API key. One cache directory
  # represents one source snapshot; use a different directory to refresh sources.
  class Client
    attr_reader :requests, :source_reads

    def initialize(cache:, offline: false, api_key: ENV['OPENALEX_API_KEY'], max_requests: 1000, allow_public: false)
      @cache, @offline, @api_key, @max_requests = cache, offline, api_key, max_requests
      @allow_public = allow_public
      @requests, @last_request = 0, nil
      @source_reads = {}
      @request_mutex = Mutex.new
    end

    def get(endpoint, params = {})
      raise ArgumentError, 'Invalid API endpoint' unless endpoint.match?(%r{\A(?:institutions|authors|works)(?:/[IAW]\d+)?\z})
      params = params.transform_keys(&:to_s).transform_values(&:to_s).sort.to_h
      raise ArgumentError, 'Pass credentials through environment only' if params.key?('api_key')
      fingerprint = Digest::SHA256.hexdigest(JSON.generate([endpoint, params]))
      path = File.join(@cache, "#{fingerprint}.json")
      if File.exist?(path)
        cached = JSON.parse(File.read(path))
        @source_reads[fingerprint] = cached.slice('endpoint', 'params', 'retrieved_at')
        return cached.fetch('response')
      end
      raise "Offline cache miss: #{endpoint}; no network request made" if @offline
      raise 'Set OPENALEX_API_KEY before live collection (do not paste it into chat)' if @api_key.to_s.empty? && !@allow_public
      if @api_key.to_s.empty? && params['cursor'] && params['cursor'] != '*'
        raise 'OpenAlex key required for cursor pagination beyond the first page'
      end

      6.times do |attempt|
        @request_mutex.synchronize do
          raise 'Request budget reached; rerun to resume from cached pages' if @requests >= @max_requests
          wait = @last_request ? 0.25 - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request) : 0
          sleep(wait) if wait.positive?
          @requests += 1
          @last_request = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
        uri = URI("https://api.openalex.org/#{endpoint}")
        uri.query = URI.encode_www_form(params)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 15
        http.read_timeout = 90
        begin
          headers = { 'User-Agent' => 'NicheRank-course-data/0.1', 'Accept' => 'application/json' }
          headers['Authorization'] = "Bearer #{@api_key}" unless @api_key.to_s.empty?
          response = http.get(uri.request_uri, headers)
          status = response.code.to_i
          if status == 429 || status >= 500
            # Stop instead of repeatedly retrying exhausted daily credits.
            body = response.body.to_s
            new_account_pace = body.match?(/new.account|pace|five.minute|5.minute|first.*dollar|first.*\$1/i)
            if status == 429 && body.match?(/daily|budget|credit/i) && !new_account_pace
              raise 'OpenAlex spending limit reached; inspect the usage status before resuming'
            end
            retry_after = response['Retry-After'].to_s
            delay = retry_after.match?(/\A\d+\z/) ? retry_after.to_i : 2**attempt
            raise "OpenAlex HTTP #{status}; #{new_account_pace ? 'new-account spending pace' : 'temporary limit'}; retry after #{delay} seconds (cached progress preserved)" if attempt == 5 || delay > 60
            sleep([delay, 1].max)
            next
          end
          raise "OpenAlex HTTP #{status} for #{endpoint}; response body omitted to protect credentials" unless status.between?(200, 299)
          result = JSON.parse(response.body)
          metadata = { 'endpoint' => endpoint, 'params' => params, 'retrieved_at' => Time.now.utc.iso8601 }
          NicheRank.atomic_json(path, metadata.merge('response' => result))
          @source_reads[fingerprint] = metadata
          return result
        rescue Timeout::Error, IOError, SystemCallError, OpenSSL::SSL::SSLError
          raise "Network failure for #{endpoint}; rerun to resume" if attempt == 5
          sleep(2**attempt)
        end
      end
    end

    def each_page(endpoint, params = {})
      return enum_for(__method__, endpoint, params) unless block_given?
      cursor, seen = '*', {}
      loop do
        raise 'Repeated cursor; refusing an endless pagination loop' if seen[cursor]
        seen[cursor] = true
        page = get(endpoint, params.merge('per_page' => 100, 'cursor' => cursor))
        results = page.fetch('results')
        yield results
        cursor = page.fetch('meta').fetch('next_cursor')
        break if cursor.nil? || results.empty?
      end
    end
  end

  class Exporter
    attr_reader :review, :duplicates, :dropped

    def initialize(universities:, professors:, aliases:, works:, tiers: [], cutoff: Date.today.iso8601, keep_empty_professors: false, dedup_series_titles: nil)
      @universities, @professors, @aliases, @works = universities, professors, aliases, works
      @cutoff = Date.iso8601(cutoff)
      @keep_empty_professors = keep_empty_professors
      @review, @duplicates, @dropped = [], [], Hash.new(0)
      @link_cache = {}
      @canonical = {}
      professors.each { |p| @canonical[p.fetch('openalex_id')] = p.fetch('openalex_id') }
      aliases.each do |a|
        id, target = a.values_at('alias_openalex_id', 'professor_openalex_id')
        raise "Alias has no canonical professor: #{target}" unless @canonical[target] == target
        raise "Conflicting alias: #{id}" if @canonical.key?(id) && @canonical[id] != target
        @canonical[id] = target
      end
      @tiers = {}
      @dedup_series_titles = (dedup_series_titles || tiers.map { |r| r['venue'] }).map { |s| NicheRank.normalize(s) }.to_set
      tiers.each do |row|
        tier, name = row.values_at('venue_tier', 'venue')
        raise 'Invalid venue tier' unless TIERS.include?(tier)
        raise 'Venue mapping needs source and kind (conference or journal_custom)' if row['source'].to_s.empty? || !%w[conference journal_custom].include?(row['kind'])
        key = NicheRank.normalize(name)
        raise 'Conflicting venue mappings' if @tiers.key?(key) && @tiers[key] != tier
        @tiers[key] = tier
      end
    end

    def issue(type, name, ids, reason, university = nil)
      @review << { 'issue_type' => type, 'university' => university, 'name_or_venue' => name,
                   'candidate_ids' => ids.join('; '), 'reason' => reason, 'status' => 'open', 'resolution' => nil }
    end

    def links(work)
      @link_cache[work.fetch('id')] ||= Array(work['authorships']).filter_map do |a|
        source_id = a.dig('author', 'id').to_s.split('/').last
        canonical = @canonical[source_id]
        next unless canonical
        [canonical, a]
      end.to_h
    end

    def export(directory, scope: 'full', extra_review: [])
      valid = @works.uniq { |w| w.fetch('id') }.select do |w|
        reason = if !TYPES.include?(TYPE_MAPPING.fetch(w['type'], w['type'])) then 'excluded_type'
                 elsif w['is_retracted'] == true then 'retracted'
                 elsif w['title'].to_s.strip.empty? then 'missing_title'
                 elsif !w['publication_year'].is_a?(Integer) then 'missing_year'
                 elsif w['publication_year'] < 2015 || w['publication_year'] > @cutoff.year then 'outside_year_window'
                 elsif w['publication_date'] && Date.iso8601(w['publication_date']) > @cutoff then 'after_cutoff'
                 elsif links(w).empty? then 'no_selected_author'
                 end
        @dropped[reason] += 1 if reason
        reason.nil?
      end.sort_by { |w| w.fetch('id') }

      # A title merge must pass the rule against every group member. This avoids
      # transitive chains merging works several years apart through a bridge.
      parent = valid.to_h { |w| [w.fetch('id'), w.fetch('id')] }
      members = valid.to_h { |w| [w.fetch('id'), [w]] }
      root = lambda { |id| parent[id] == id ? id : parent[id] = root.call(parent[id]) }
      union = lambda do |a, b|
        left, right = root.call(a), root.call(b)
        unless left == right
          parent[right] = left
          members[left].concat(members.delete(right))
        end
      end
      valid.reject { |w| NicheRank.doi(w['doi']).empty? }.group_by { |w| NicheRank.doi(w['doi']) }.each_value do |group|
        group.drop(1).each { |w| union.call(group.first['id'], w['id']) }
      end
      valid.group_by { |w| NicheRank.normalize(w['title']) }.each_value do |group|
        group.combination(2) do |a, b|
          next if root.call(a['id']) == root.call(b['id'])
          members_a = members.fetch(root.call(a['id']))
          members_b = members.fetch(root.call(b['id']))
          safe = members_a.product(members_b).all? do |x, y|
            doi_x, doi_y = NicheRank.doi(x['doi']), NicheRank.doi(y['doi'])
            conflicting_formal_dois = !doi_x.empty? && !doi_y.empty? && doi_x != doi_y &&
              !NicheRank.preprint_record?(x) && !NicheRank.preprint_record?(y)
            NicheRank.normalize(x['title']) == NicheRank.normalize(y['title']) &&
              !GENERIC_TITLES.include?(NicheRank.normalize(x['title'])) &&
              !@dedup_series_titles.include?(NicheRank.normalize(x['title'])) &&
              !conflicting_formal_dois &&
              (x['publication_year'] - y['publication_year']).abs <= 1 && !(links(x).keys & links(y).keys).empty?
          end
          if safe
            union.call(a['id'], b['id'])
          else
            issue('possible_duplicate', a['title'], [a['id'], b['id']].map { |id| NicheRank.short_id(id, 'W') }, 'Title collision fails conservative merge rule; left separate')
          end
        end
      end
      papers, authorships = [], []
      valid.group_by { |w| root.call(w['id']) }.each_value do |group|
        ordered = group.sort_by { |w| [w['type'] == 'preprint' ? 1 : 0, -w.fetch('cited_by_count', 0).to_i, w['id']] }
        retained = ordered.first
        paper_id = NicheRank.short_id(retained['id'], 'W')
        ordered.drop(1).each do |w|
          @duplicates << { 'discarded_openalex_id' => NicheRank.short_id(w['id'], 'W'), 'retained_openalex_id' => paper_id,
                           'reason' => NicheRank.doi(w['doi']) != '' && NicheRank.doi(w['doi']) == NicheRank.doi(retained['doi']) ? 'doi' : 'safe_title' }
        end
        papers << paper_row(retained).merge('citations' => group.map { |w| w.fetch('cited_by_count', 0).to_i }.max)
        # Retained-record values take precedence; discarded records fill missing authors.
        combined = {}
        ordered.each { |w| links(w).each { |professor, a| combined[professor] ||= a } }
        combined.each do |professor, a|
          position = a['author_position']
          position = nil unless %w[first middle last].include?(position)
          authorships << { 'professor_openalex_id' => professor, 'paper_openalex_id' => paper_id,
                           'position' => position, 'is_corresponding' => a['is_corresponding'] }
        end
      end
      included = authorships.to_h { |a| [a['professor_openalex_id'], true] }
      professors, omitted = @professors.partition { |p| included.key?(p['openalex_id']) }
      omitted.each { |p| issue('no_papers', p['name'], [p['openalex_id']], "No qualifying paper in this collected scope; #{@keep_empty_professors ? 'professor retained with zero papers' : 'omitted'}", p['university_openalex_id']) }
      if @keep_empty_professors
        professors = @professors
        omitted = []
      end
      retained_ids = professors.map { |p| p['openalex_id'] }.to_set
      papers.group_by { |p| p['venue'] }.each do |venue, rows|
        next if venue.to_s.empty? || @tiers.key?(NicheRank.normalize(venue)) || rows.size < 20
        issue('venue_match', venue, [], "#{rows.size} retained papers; needs verified mapping")
      end
      tables = { 'universities' => @universities, 'professors' => professors, 'papers' => papers,
                 'authorships' => authorships, 'author_aliases' => @aliases.select { |a| retained_ids.include?(a['professor_openalex_id']) },
                 'duplicates' => @duplicates, 'review' => (extra_review + @review).uniq }
      tables.each do |name, rows|
        rows.sort_by! { |r| HEADERS[name].map { |h| r[h].to_s } }
        NicheRank.write_csv(File.join(directory, "#{name}.csv"), HEADERS[name], rows)
      end
      errors = Validator.new(directory, allow_empty_professors: @keep_empty_professors).errors
      raise "Export failed validation: #{errors.join('; ')}" unless errors.empty?
      counts = tables.transform_values(&:size)
      manifest = { 'schema_version' => '1', 'scope' => scope, 'collection_cutoff' => @cutoff.iso8601,
                   'keep_empty_professors' => @keep_empty_professors,
                   'publication_year_start' => 2015, 'counts' => counts, 'dropped_records' => @dropped,
                   'source_to_csv_type_mapping' => TYPE_MAPPING,
                   'omitted_professors' => omitted.map { |p| p.slice('openalex_id', 'name') },
                   'papers_with_abstracts' => papers.count { |p| !p['abstract'].to_s.empty? },
                   'abstract_coverage_percent' => papers.empty? ? 0 : (100.0 * papers.count { |p| !p['abstract'].to_s.empty? } / papers.size).round(2),
                   'professors_per_university' => professors.group_by { |p| p['university_openalex_id'] }.transform_values(&:size),
                   'papers_per_university' => @universities.to_h { |u| ids = professors.select { |p| p['university_openalex_id'] == u['openalex_id'] }.map { |p| p['openalex_id'] }.to_set; [u['openalex_id'], authorships.select { |a| ids.include?(a['professor_openalex_id']) }.map { |a| a['paper_openalex_id'] }.uniq.size] },
                   'limitations' => ['Current roster affiliation is used, not affiliation at publication time.', 'Custom journal tiers are not CORE conference ranks.', 'Author aliases and faculty eligibility require documented review.'] }
      NicheRank.atomic_json(File.join(directory, 'manifest.json'), manifest)
      File.write(File.join(directory, 'README.md'), "# NicheRank dataset\n\nScope: #{scope}. Collection cutoff: #{@cutoff}.\n\n#{counts.map { |k, v| "- #{k}: #{v}" }.join("\n")}\n\nAbstract coverage: #{manifest['abstract_coverage_percent']}%.\n\nSee manifest.json, review.csv and the manual source files for exclusions, provenance, and limitations.\n")
      manifest
    end

    def paper_row(w)
      location = w['primary_location'] || {}
      venue = location.dig('source', 'display_name')
      venue = 'arXiv' if venue.to_s.empty? && location['landing_page_url'].to_s.match?(%r{\Ahttps?://(?:www\.)?arxiv\.org/}i)
      { 'openalex_id' => NicheRank.short_id(w['id'], 'W'), 'title' => w['title'], 'abstract' => NicheRank.abstract(w['abstract_inverted_index']),
        'year' => w['publication_year'], 'type' => TYPE_MAPPING.fetch(w['type'], w['type']), 'venue' => venue,
        'venue_tier' => (%w[article conference-paper proceedings-article].include?(w['type']) ? @tiers[NicheRank.normalize(venue)] : nil),
        'citations' => w['cited_by_count'], 'doi' => NicheRank.doi(w['doi']).then { |d| d.empty? ? nil : d },
        'primary_topic' => w.dig('primary_topic', 'display_name'), 'field' => w.dig('primary_topic', 'field', 'display_name'),
        'keywords' => Array(w['keywords']).map { |k| k['display_name'] }.compact.join('; '),
        'is_open_access' => w.dig('open_access', 'is_oa'), 'oa_url' => w.dig('open_access', 'oa_url'), 'language' => w['language'] }
    end
  end

  class Validator
    def initialize(directory, allow_empty_professors: false)
      @directory = directory
      @allow_empty_professors = allow_empty_professors
    end

    def errors
      result, tables = [], {}
      HEADERS.each do |name, headers|
        path = File.join(@directory, "#{name}.csv")
        unless File.exist?(path)
          result << "Missing #{name}.csv"
          next
        end
        csv = CSV.read(path, headers: true, encoding: 'bom|utf-8')
        result << "Unexpected header in #{name}.csv" unless csv.headers == headers
        tables[name] = csv.map(&:to_h)
      end
      return result unless result.empty?
      %w[universities professors papers].zip(%w[I A W]).each do |name, kind|
        ids = tables[name].map { |r| r['openalex_id'] }
        result << "Duplicate IDs in #{name}" unless ids.uniq == ids
        tables[name].each do |row|
          result << "Invalid ID in #{name}" unless row['openalex_id'].to_s.match?(/\A#{kind}\d+\z/)
          required = name == 'papers' ? %w[title year] : name == 'professors' ? %w[name title university_openalex_id] : %w[name]
          required.each { |k| result << "Missing #{k} in #{name}: #{row['openalex_id']}" if row[k].to_s.strip.empty? }
        end
      end
      university_ids = tables['universities'].map { |r| r['openalex_id'] }.to_set
      professor_ids = tables['professors'].map { |r| r['openalex_id'] }.to_set
      paper_ids = tables['papers'].map { |r| r['openalex_id'] }.to_set
      tables['professors'].each do |row|
        result << 'Broken professor/university reference' unless university_ids.include?(row['university_openalex_id'])
        result << 'Invalid match confidence' unless %w[high medium manual].include?(row['match_confidence'])
      end
      tables['papers'].each do |row|
        result << 'Invalid year' unless row['year'].to_s.match?(/\A\d{4}\z/) && row['year'].to_i >= 2015
        result << 'Invalid paper type' unless TYPES.include?(row['type'])
        result << 'Invalid venue tier' unless row['venue_tier'].to_s.empty? || TIERS.include?(row['venue_tier'])
        result << 'Invalid OA boolean' unless [nil, '', 'true', 'false'].include?(row['is_open_access'])
      end
      { 'authorships' => %w[professor_openalex_id paper_openalex_id], 'author_aliases' => %w[professor_openalex_id alias_openalex_id] }.each do |name, keys|
        pairs = tables[name].map { |r| r.values_at(*keys) }
        result << "Duplicate relationship in #{name}" unless pairs.uniq == pairs
        tables[name].each do |r|
          result << "Broken professor reference in #{name}" unless professor_ids.include?(r['professor_openalex_id'])
          if name == 'authorships'
            result << 'Broken paper reference' unless paper_ids.include?(r['paper_openalex_id'])
            result << 'Invalid authorship position' unless [nil, '', 'first', 'middle', 'last'].include?(r['position'])
            result << 'Invalid corresponding boolean' unless [nil, '', 'true', 'false'].include?(r['is_corresponding'])
          else
            result << 'Invalid alias ID' unless r['alias_openalex_id'].to_s.match?(/\AA\d+\z/)
            result << 'Alias collides with canonical professor' if professor_ids.include?(r['alias_openalex_id'])
          end
        end
      end
      alias_ids = tables['author_aliases'].map { |r| r['alias_openalex_id'] }
      result << 'Alias assigned to multiple professors' unless alias_ids.uniq == alias_ids
      authors = tables['authorships'].map { |r| r['professor_openalex_id'] }.to_set
      result << 'Professor with no exported papers' unless @allow_empty_professors || (professor_ids - authors).empty?
      linked_papers = tables['authorships'].map { |r| r['paper_openalex_id'] }.to_set
      result << 'Paper with no exported professor' unless (paper_ids - linked_papers).empty?
      discarded = tables['duplicates'].map { |r| r['discarded_openalex_id'] }
      result << 'Duplicate discarded ID' unless discarded.uniq == discarded
      tables['duplicates'].each do |r|
        result << 'Invalid discarded work ID' unless r['discarded_openalex_id'].to_s.match?(/\AW\d+\z/)
        result << 'Invalid duplicate reference' unless paper_ids.include?(r['retained_openalex_id']) && !paper_ids.include?(r['discarded_openalex_id'])
      end
      result.uniq
    rescue CSV::MalformedCSVError => e
      ["Malformed CSV: #{e.message}"]
    end
  end
end
