require "rails_helper"
require_relative "../support/embedding_helpers"

RSpec.describe "Venue-quality selection" do
  include EmbeddingHelpers

  def paper(venue, type: "conference-paper")
    Paper.create!(openalex_id: "W98#{@id = (@id || 0) + 1}", title: "Learning #{@id}",
                  venue: venue, year: 2024, paper_type: type)
  end

  def rating(venue, source, grade, kind: "conference")
    VenueRating.create!(venue: venue, source: source, ranking: grade, kind: kind, match_method: "exact_title")
  end

  it "matches exact source, grade and venue for published records, keeping missing ratings explicit" do
    conference = paper("Shared name")
    conference_article = paper("Shared name", type: "article")
    journal = paper("Journal", type: "article")
    preprint = paper("Shared name", type: "preprint")
    absent = paper(nil)
    different_case = paper("shared name")
    rating("shared name", "era2010", "A*", kind: "conference") # invalid source/kind pair
    rating("shared name", "icore2026", "Q1") # unsupported source/grade pair
    rating("Shared name", "icore2026", "A*")
    rating("Journal", "era2010", "B", kind: "journal")
    rating("Journal", "scimago2025", "Q1", kind: "journal")
    expect(Paper.with_venue_rating("icore2026:A*")).to contain_exactly(conference, conference_article)
    expect(Paper.with_venue_rating("era2010:B")).to contain_exactly(journal)
    expect(Paper.with_venue_rating("era2010:A*")).to be_empty
    expect(Paper.with_venue_rating("unrated")).to contain_exactly(preprint, absent, different_case)
    expect(journal.listed_venue_ratings.map(&:label)).to eq(["ERA 2010 · B", "SCImago 2025 · Q1"])
    expect(different_case.listed_venue_ratings).to be_empty
    expect(conference_article.listed_venue_ratings.map(&:label)).to eq(["ICORE 2026 · A*"])
    expect(preprint.listed_venue_ratings).to be_empty
  end

  it "counts a paper with two rating sources once in the institution score" do
    school = University.create!(openalex_id: "I98001", name: "Northbridge")
    author = Professor.create!(openalex_id: "A98001", name: "Alice", title: "Professor", university: school, match_confidence: "manual")
    publication = paper("NeurIPS", type: "article")
    Authorship.create!(professor: author, paper: publication)
    rating("NeurIPS", "era2010", "A", kind: "journal")
    rating("NeurIPS", "scimago2025", "Q1", kind: "journal")
    expect(Paper.with_venue_rating("rated").count).to eq(1)
    expect(Ranking.new(RankingFilters.new(venue_rating: "rated")).rows.map(&:score)).to eq([1.0])
  end

  it "filters keyword results before pagination and safely ignores unsupported input" do
    paper("Unknown")
    selected = [paper("NeurIPS"), paper("NeurIPS")]
    rating("NeurIPS", "icore2026", "A*")
    stub_const("Paper::SEARCH_LIMIT", 1)
    expect(Paper.search("learning", page: 2, venue_rating: "icore2026:A*")).to eq([selected.last])
    expect(Paper.with_venue_rating("icore2026:A*' OR 1=1 --").count).to eq(3)
    expect(RankingFilters.new(venue_rating: "bad").to_params).not_to have_key(:venue_rating)
    [nil, ["rated"], ActionController::Parameters.new(source: "icore2026")].each do |input|
      expect(Paper.with_venue_rating(input).count).to eq(3)
      expect(RankingFilters.new(venue_rating: input).to_params).not_to have_key(:venue_rating)
    end
  end

  it "filters both semantic and hybrid candidates before their result limit" do
    closest = paper("Unrated")
    rated = paper("NeurIPS")
    embed_paper!(closest, concept_vector(0))
    embed_paper!(rated, concept_vector(0, toward: 1, weight: 0.5))
    rating("NeurIPS", "icore2026", "A*")
    stub_query_embedding("learning" => concept_vector(0))
    stub_const("Paper::SEMANTIC_LIMIT", 1)
    expect(Paper.semantic_ids("learning", venue_rating: "rated")).to eq([rated.id])
    expect(Paper.hybrid_ids("learning", venue_rating: "rated")).to eq([rated.id])
    expect(Paper.semantic_ids("learning", venue_rating: "era2010:A")).to be_empty
  end
end
