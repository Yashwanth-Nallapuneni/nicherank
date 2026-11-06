# Fixtures mirror tests/spec/features/*_spec.rb: same models, attributes and defaults.
module FixtureHelpers
  def universities = (@universities ||= {})
  def professors = (@professors ||= {})
  def papers = (@papers ||= {})

  def next_openalex_id(prefix)
    @openalex_seq = (@openalex_seq || 910_000) + 1
    "#{prefix}#{@openalex_seq}"
  end

  def university_named(name)
    universities[name] ||= University.create!(openalex_id: next_openalex_id("I"), name: name)
  end

  def professor_named(name, university_name)
    professors[name] ||= Professor.create!(
      openalex_id: next_openalex_id("A"), name: name, title: "Professor",
      university_id: university_named(university_name).id,
      homepage_url: "https://example.org/#{name.split.first.downcase}", match_confidence: "manual"
    )
  end

  def store_paper(attributes)
    papers[attributes[:title]] = Paper.create!({
      openalex_id: next_openalex_id("W"), year: 2024, venue: "NeurIPS",
      paper_type: "conference-paper", venue_tier: "A*", venue_tier_source: "core2023",
      citations: 0, abstract: nil, keywords: nil, primary_topic: nil
    }.merge(attributes))
  end

  def add_author(professor, paper)
    Authorship.create!(professor_id: professor.id, paper_id: paper.id)
  end
end
World(FixtureHelpers)

Given("the following universities and professors exist:") do |table|
  table.hashes.each { |row| professor_named(row["professor"], row["university"]) }
end

Given("the following qualifying papers are stored:") do |table|
  table.hashes.each do |row|
    paper = store_paper(title: row["title"], year: row["year"].to_i, venue: row["venue"])
    add_author(professors.fetch(row["professor"]), paper)
  end
end

Given("the following papers are stored:") do |table|
  # Empty cells mean NULL; other columns keep the 2024 NeurIPS defaults.
  table.hashes.each { |row| store_paper(row.transform_keys(&:to_sym).transform_values(&:presence)) }
end

Given("{string} from {string} is an author of every paper") do |professor, university|
  author = professor_named(professor, university)
  papers.each_value { |paper| add_author(author, paper) }
end

Given("{string} from {string} is also an author of {string}") do |professor, university, title|
  add_author(professor_named(professor, university), papers.fetch(title))
end

Given("{string} is the only university in the test database") do |name|
  expect(University.count).to eq(0)
  @only_university = university_named(name)
end

Given("its professor {string} has a stored {int} {word} paper titled {string}") do |name, year, venue, title|
  add_author(professor_named(name, @only_university.name), store_paper(title: title, year: year, venue: venue))
end

Given("NeurIPS belongs to {string} and SIGMOD belongs to {string}") do |neurips_area, sigmod_area|
  expect(VenueArea.venues([neurips_area])).to include("neurips")
  expect(VenueArea.venues([sigmod_area])).to include("sigmod")
end

Given(/^(.+)'s website is "([^"]*)"$/) do |name, url|
  professors.fetch(name).update!(homepage_url: url)
end
