# frozen_string_literal: true

require "rails_helper"
require_relative "../support/ranking_helpers"
require_relative "../support/embedding_helpers"

# Story: As a student, I want to search papers by meaning so that papers that
# describe my topic in different words still show up.
RSpec.describe "Searching papers by meaning", type: :feature do
  include RankingHelpers
  include EmbeddingHelpers

  let!(:uni) { University.create!(openalex_id: "I950001", name: "Northbridge University") }
  let!(:alice) do
    Professor.create!(openalex_id: "A950001", name: "Alice Researcher", title: "Professor",
                      university_id: uni.id, match_confidence: "manual")
  end

  def store(openalex_id, title, vector)
    paper = Paper.create!(openalex_id: openalex_id, title: title, year: 2024, venue: "NeurIPS",
                          paper_type: "conference-paper", venue_tier: "A*", venue_tier_source: "core2023", citations: 0)
    Authorship.create!(professor_id: alice.id, paper_id: paper.id)
    embed_paper!(paper, vector)
    paper
  end

  before do
    store("W950001", "Imitation learning from human video", concept_vector(0))
    store("W950002", "Query optimization for column stores", concept_vector(2))
    stub_query_embedding("teaching robots by showing them" => concept_vector(0))
  end

  def search(query, mode)
    open_rankings
    fill_in "Search papers", with: query
    choose mode
    click_button "Search"
  end

  def titles = all('[data-testid="paper-title"]').map(&:text)

  it "finds a paper with no words in common with the query" do
    search("teaching robots by showing them", "Keyword")
    expect(page).to have_text("No papers found")

    search("teaching robots by showing them", "Meaning (semantic)")
    expect(titles.first).to eq("Imitation learning from human video")
    expect(page).to have_checked_field("Meaning (semantic)")
  end

  it "keeps the chosen mode when sorting and when going back from a professor" do
    search("teaching robots by showing them", "Both (hybrid)")
    select "Year (newest first)", from: "Sort by"
    click_button "Sort"
    expect(page).to have_checked_field("Both (hybrid)")

    within(find('[data-testid="ranking-row"]', text: "Northbridge University")) { click_button "Show faculty" }
    click_link "View papers"
    click_link "Back to rankings"
    expect(page).to have_checked_field("Both (hybrid)")
  end

  it "falls back to keyword results with a notice when the embedding service fails" do
    allow(Paper).to receive(:query_embedding).and_raise(VoyageClient::Error, "down")
    search("query optimization", "Meaning (semantic)")

    expect(page).to have_text("Search by meaning is unavailable right now")
    expect(titles).to eq(["Query optimization for column stores"])
    expect(page).to have_checked_field("Keyword")
  end

  it "uses keyword search by default" do
    open_rankings
    expect(page).to have_checked_field("Keyword")
  end
end
