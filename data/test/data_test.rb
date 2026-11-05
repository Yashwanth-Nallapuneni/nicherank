# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../script/data/lib/nicherank'
require_relative '../script/data/stanford_roster'
require_relative '../script/data/collect'

class DataTest < Minitest::Test
  def university
    { 'openalex_id' => 'I1', 'name' => 'Test University' }
  end

  def professor(id = 'A1')
    { 'openalex_id' => id, 'name' => "Test #{id}", 'university_openalex_id' => 'I1', 'title' => 'Professor', 'match_confidence' => 'manual' }
  end

  def work(id, year: 2024, type: 'article', author: 'A1', title: 'Graph neural networks', doi: nil, citations: 1)
    { 'id' => "https://openalex.org/#{id}", 'title' => title, 'publication_year' => year, 'type' => type, 'doi' => doi,
      'cited_by_count' => citations, 'authorships' => [{ 'author' => { 'id' => "https://openalex.org/#{author}" }, 'author_position' => 'first', 'is_corresponding' => false }] }
  end

  def exported(works, professors: [professor], aliases: [])
    Dir.mktmpdir do |dir|
      ex = NicheRank::Exporter.new(universities: [university], professors: professors, aliases: aliases, works: works, cutoff: '2026-11-04')
      manifest = ex.export(dir, scope: 'synthetic_test_only')
      yield dir, ex, manifest
    end
  end

  def test_generic_titles_with_different_dois_are_not_collapsed
    items = [work('W1', title: 'Introduction', doi: '10.1000/one'),
             work('W2', title: 'Introduction', doi: '10.1000/two')]
    exported(items) do |_dir, exporter, manifest|
      assert_equal 2, manifest.dig('counts', 'papers')
      assert_empty exporter.duplicates
    end
  end

  def test_generic_titles_with_the_same_doi_still_deduplicate
    items = [work('W1', title: 'Introduction', doi: '10.1000/same'),
             work('W2', title: 'Introduction', doi: 'https://doi.org/10.1000/same')]
    exported(items) do |_dir, exporter, manifest|
      assert_equal 1, manifest.dig('counts', 'papers')
      assert_equal 'doi', exporter.duplicates.first.fetch('reason')
    end
  end

  def test_different_formal_dois_require_more_than_matching_title_and_author
    exported([work('W1', doi: '10.1000/conference'), work('W2', doi: '10.1000/journal')]) do |_dir, exporter, manifest|
      assert_equal 2, manifest.dig('counts', 'papers')
      assert_empty exporter.duplicates
    end
  end

  def test_arxiv_doi_can_merge_with_a_matching_published_paper
    exported([work('W1', doi: '10.48550/arXiv.2401.12345'), work('W2', doi: '10.1000/published')]) do |_dir, exporter, manifest|
      assert_equal 1, manifest.dig('counts', 'papers')
      assert_equal 1, exporter.duplicates.size
    end
  end

  def test_preprints_do_not_inherit_a_journal_tier
    Dir.mktmpdir do |directory|
      record = work('W1', type: 'preprint').merge('primary_location' => { 'source' => { 'display_name' => 'Example Journal' } })
      exporter = NicheRank::Exporter.new(universities: [university], professors: [professor], aliases: [], works: [record],
        tiers: [{ 'venue' => 'Example Journal', 'venue_tier' => 'A', 'kind' => 'journal_custom', 'source' => 'Project policy' }])
      exporter.export(directory)
      assert_nil NicheRank.read_csv(File.join(directory, 'papers.csv')).first['venue_tier']
    end
  end

  def test_tier_enrichment_does_not_change_the_frozen_dedup_vocabulary
    Dir.mktmpdir do |directory|
      items = [work('W1', title: 'A Descriptive Conference Name'), work('W2', title: 'A Descriptive Conference Name')]
      exporter = NicheRank::Exporter.new(universities: [university], professors: [professor], aliases: [], works: items,
        tiers: [{ 'venue' => 'A Descriptive Conference Name', 'venue_tier' => 'A', 'kind' => 'conference', 'source' => 'CORE2023' }], dedup_series_titles: [])
      manifest = exporter.export(directory)
      assert_equal 1, manifest.dig('counts', 'papers')
    end
  end

  def test_abstract_repeated_words
    assert_equal 'we test we', NicheRank.abstract('we' => [0, 2], 'test' => [1])
    assert_nil NicheRank.abstract(nil)
    assert_raises(ArgumentError) { NicheRank.abstract('x' => [-1]) }
  end

  def test_ids_and_doi_normalization
    assert_equal 'A123', NicheRank.short_id('https://openalex.org/A123', 'A')
    assert_raises(ArgumentError) { NicheRank.short_id('W123', 'A') }
    assert_equal '10.1000/abc', NicheRank.doi('https://doi.org/10.1000/ABC')
  end

  def test_doi_merge_retains_published_metadata_max_citations_and_authors
    a = work('W1', type: 'preprint', doi: 'https://doi.org/10.1/TEST', citations: 20)
    b = work('W2', doi: '10.1/test', author: 'A2', citations: 5)
    exported([a, b], professors: [professor, professor('A2')]) do |dir, _, manifest|
      assert_equal 1, manifest['counts']['papers']
      paper = NicheRank.read_csv("#{dir}/papers.csv").first
      assert_equal 'W2', paper['openalex_id']
      assert_equal '20', paper['citations']
      assert_equal 2, NicheRank.read_csv("#{dir}/authorships.csv").size
      assert_equal 'W2', NicheRank.read_csv("#{dir}/duplicates.csv").first['retained_openalex_id']
    end
  end

  def test_safe_title_merge
    exported([work('W1', year: 2023, type: 'preprint', title: 'Graph: Neural Networks!'), work('W2')]) do |_, _, m|
      assert_equal 1, m['counts']['papers']
    end
  end

  def test_current_api_conference_type_maps_to_agreed_csv_value
    exported([work('W1', type: 'conference-paper')]) do |dir, _, manifest|
      assert_equal 'proceedings-article', NicheRank.read_csv("#{dir}/papers.csv").first['type']
      assert_equal({ 'conference-paper' => 'proceedings-article' }, manifest['source_to_csv_type_mapping'])
      assert_includes NicheRank::SOURCE_TYPES, 'conference-paper'
      refute_includes NicheRank::SOURCE_TYPES, 'proceedings-article'
    end
  end

  def test_title_collision_different_authors_not_merged
    exported([work('W1'), work('W2', author: 'A2')], professors: [professor, professor('A2')]) do |_, ex, m|
      assert_equal 2, m['counts']['papers']
      assert_equal 'possible_duplicate', ex.review.first['issue_type']
    end
  end

  def test_transitive_title_chain_does_not_merge_distant_years
    exported([work('W1', year: 2022), work('W2', year: 2023), work('W3', year: 2024)]) do |_, _, m|
      assert_equal 2, m['counts']['papers']
    end
  end

  def test_aliases_map_to_canonical
    exported([work('W1', author: 'A9')], aliases: [{ 'professor_openalex_id' => 'A1', 'alias_openalex_id' => 'A9' }]) do |dir, _, _|
      assert_equal 'A1', NicheRank.read_csv("#{dir}/authorships.csv").first['professor_openalex_id']
    end
  end

  def test_retracted_old_future_and_missing_records_are_excluded
    rows = [work('W1'), work('W2', year: 2014), work('W3').merge('is_retracted' => true), work('W4', title: ''), work('W5', year: nil), work('W6', type: 'dataset'), work('W7').merge('publication_date' => '2026-12-01')]
    exported(rows) { |_, _, m| assert_equal 1, m['counts']['papers']; assert_equal 6, m['dropped_records'].values.sum }
  end

  def test_csv_multiline_unicode_and_missing_booleans
    exported([work('W1', title: "Graph, \"networks\"\n研究").merge('authorships' => [{ 'author' => { 'id' => 'https://openalex.org/A1' } }])]) do |dir, _, _|
      assert_equal "Graph, \"networks\"\n研究", NicheRank.read_csv("#{dir}/papers.csv").first['title']
      assert_nil NicheRank.read_csv("#{dir}/authorships.csv").first['is_corresponding']
      assert_empty NicheRank::Validator.new(dir).errors
    end
  end

  def test_no_paper_professor_is_reported
    exported([], professors: [professor]) do |_, ex, m|
      assert_equal 0, m['counts']['professors']
      assert_equal 'no_papers', ex.review.first['issue_type']
    end
  end

  def test_validator_catches_broken_references
    exported([work('W1')]) do |dir, _, _|
      rows = NicheRank.read_csv("#{dir}/authorships.csv")
      rows.first['paper_openalex_id'] = 'W999'
      NicheRank.write_csv("#{dir}/authorships.csv", NicheRank::HEADERS['authorships'], rows)
      assert_includes NicheRank::Validator.new(dir).errors, 'Broken paper reference'
    end
  end

  def test_deterministic_export
    rows = [work('W2'), work('W1', year: 2023)]
    exported(rows) do |dir, _, _|
      before = Dir["#{dir}/*"].to_h { |p| [File.basename(p), File.binread(p)] }
      NicheRank::Exporter.new(universities: [university], professors: [professor], aliases: [], works: rows.reverse, cutoff: '2026-11-04').export(dir, scope: 'synthetic_test_only')
      assert_equal before, Dir["#{dir}/*"].to_h { |p| [File.basename(p), File.binread(p)] }
    end
  end

  def test_offline_cache_needs_no_key
    Dir.mktmpdir do |dir|
      params = { 'search' => 'Test' }
      fingerprint = Digest::SHA256.hexdigest(JSON.generate(['authors', params]))
      NicheRank.atomic_json("#{dir}/#{fingerprint}.json", { 'response' => { 'results' => [] } })
      client = NicheRank::Client.new(cache: dir, offline: true, api_key: nil)
      assert_equal({ 'results' => [] }, client.get('authors', params))
      assert_equal 0, client.requests
      assert_raises(RuntimeError) { client.get('works') }
    end
  end

  def test_no_key_fails_before_network
    Dir.mktmpdir do |dir|
      client = NicheRank::Client.new(cache: dir, api_key: nil)
      assert_raises(RuntimeError) { client.get('authors') }
      assert_equal 0, client.requests
    end
  end

  def test_cursor_pages_and_loop_guard
    client = NicheRank::Client.new(cache: '/unused', offline: true)
    pages = [{ 'results' => [1], 'meta' => { 'next_cursor' => 'next' } }, { 'results' => [2], 'meta' => { 'next_cursor' => nil } }]
    client.define_singleton_method(:get) { |_, _| pages.shift }
    assert_equal [[1], [2]], client.each_page('works').to_a
    client.define_singleton_method(:get) { |_, _| { 'results' => [1], 'meta' => { 'next_cursor' => '*' } } }
    assert_raises(RuntimeError) { client.each_page('works').to_a }
  end

  def test_stanford_parser_preserves_titles_and_requires_review
    html = '<div class="su-card__contents"><h3 class="su-card__link"><a href="/people/a">A &amp; B</a></h3>Assistant Professor of Computer Science</div>'
    row = NicheRank::StanfordRoster.extract(html).first
    assert_equal 'A & B', row['name']
    assert_equal 'Assistant Professor of Computer Science', row['title']
    assert_equal 'https://www.cs.stanford.edu/people/a', row['homepage_url']
  end

  def test_request_cap_stops_before_network_and_does_not_print_key
    Dir.mktmpdir do |dir|
      client = NicheRank::Client.new(cache: dir, api_key: 'test-secret-never-print', max_requests: 0)
      error = assert_raises(RuntimeError) { client.get('authors') }
      refute_includes error.message, 'test-secret'
      assert_equal 0, client.requests
      assert_empty Dir["#{dir}/*"]
    end
  end

  def test_collector_to_csv_offline_with_simulated_source
    Dir.mktmpdir do |dir|
      manual = File.join(dir, 'manual')
      FileUtils.mkdir_p(manual)
      NicheRank.write_csv("#{manual}/universities.csv", NicheRank::HEADERS['universities'], [university])
      NicheRank.write_csv("#{manual}/faculty_raw.csv", %w[university name title homepage_url source_url],
                         [{ 'university' => university['name'], 'name' => 'Test A1', 'title' => 'Professor', 'source_url' => 'https://example.org' }])
      NicheRank.write_csv("#{manual}/author_matches.csv", %w[university name openalex_id match_confidence status evidence_url alias_checked_on],
                         [{ 'university' => university['name'], 'name' => 'Test A1', 'openalex_id' => 'A1', 'match_confidence' => 'manual', 'status' => 'verified', 'evidence_url' => 'https://example.org', 'alias_checked_on' => '2026-11-04' }])
      %w[author_aliases review].each { |name| NicheRank.write_csv("#{manual}/#{name}.csv", NicheRank::HEADERS[name], []) }
      NicheRank.write_csv("#{manual}/venue_tiers.csv", %w[venue venue_tier kind source notes], [])
      raw_work = work('W1')
      fake = Object.new
      fake.define_singleton_method(:requests) { 0 }
      fake.define_singleton_method(:source_reads) { {} }
      fake.define_singleton_method(:get) do |endpoint, _params = {}|
        endpoint == 'authors/A1' ? { 'works_count' => 10, 'summary_stats' => { 'h_index' => 3 } } : { 'results' => [{ 'publication_year' => 2001 }] }
      end
      fake.define_singleton_method(:each_page) { |_, _, &block| block.call([raw_work]) }
      options = { cache: "#{dir}/cache", offline: true, max_requests: 0, output: "#{dir}/out", snapshot: "#{dir}/snapshot.json", cutoff: '2026-11-04', limit: 1 }
      runner = NicheRank::Runner.new(options)
      runner.instance_variable_set(:@manual, manual)
      runner.instance_variable_set(:@client, fake)
      capture_io { runner.run('collect') }
      assert_empty NicheRank::Validator.new(options[:output]).errors
      assert_equal '2001', NicheRank.read_csv("#{dir}/out/professors.csv").first['first_pub_year']
      manifest = JSON.parse(File.read("#{dir}/out/manifest.json"))
      assert_equal 'sample', manifest['scope']
      assert_equal false, manifest['complete_ten_school_dataset']
      assert_equal 1, manifest['counts']['authorships']
      capture_io { runner.run('export') }
      assert_empty NicheRank::Validator.new(options[:output]).errors
    end
  end

  def test_candidate_request_cap_preserves_completed_suggestions
    Dir.mktmpdir do |dir|
      manual = File.join(dir, 'manual')
      NicheRank.write_csv("#{manual}/universities.csv", NicheRank::HEADERS['universities'], [university])
      NicheRank.write_csv("#{manual}/faculty_raw.csv", %w[university name],
                         [{ 'university' => university['name'], 'name' => 'First' }, { 'university' => university['name'], 'name' => 'Second' }])
      fake = Object.new
      calls = 0
      fake.define_singleton_method(:get) do |_, _|
        calls += 1
        raise 'Request budget reached' if calls > 2
        { 'results' => [{ 'id' => 'https://openalex.org/A1', 'display_name' => 'First' }] }
      end
      runner = NicheRank::Runner.new(cache: "#{dir}/cache", offline: true, max_requests: 0, output: "#{dir}/out")
      runner.instance_variable_set(:@manual, manual)
      runner.instance_variable_set(:@client, fake)
      capture_io { assert_raises(RuntimeError) { runner.run('candidates') } }
      assert_equal 1, NicheRank.read_csv("#{dir}/out/author_candidates.csv").size
      progress = JSON.parse(File.read("#{dir}/out/candidate_progress.json"))
      assert_equal 1, progress['completed_roster_entries']
      assert_equal false, progress['complete']
    end
  end
end
