# frozen_string_literal: true

require "rails_helper"
require_relative "../support/ranking_helpers"
require_relative "../support/embedding_helpers"

# Story 14: As a student, I want universities ranked for my research topic, not only for
# whole areas, so that I can find the strongest groups in my niche.
RSpec.describe "Ranking universities by a search topic", type: :feature do
  include RankingHelpers
  include EmbeddingHelpers

  let!(:north) { University.create!(openalex_id: "I970001", name: "Northbridge University") }
  let!(:south) { University.create!(openalex_id: "I970002", name: "Southfield University") }
  let!(:alice) { professor("Alice Researcher", north) }
  let!(:bob) { professor("Bob Builder", south) }

  def professor(name, university)
    @prof_seq = (@prof_seq || 0) + 1
    Professor.create!(openalex_id: "A97#{format('%04d', @prof_seq)}", name: name, title: "Professor",
                      university_id: university.id, match_confidence: "manual")
  end

  def store(title, author, vector, year: 2024)
    @paper_seq = (@paper_seq || 0) + 1
    paper = Paper.create!(openalex_id: "W97#{format('%04d', @paper_seq)}", title: title, year: year, venue: "NeurIPS",
                          paper_type: "conference-paper", venue_tier: "A*", venue_tier_source: "core2023", citations: 0)
    Authorship.create!(professor_id: author.id, paper_id: paper.id)
    embed_paper!(paper, vector)
    paper
  end

  before do
    store("Imitation learning from human video", alice, concept_vector(0))
    store("Query optimization for column stores", bob, concept_vector(2))
    store("Indexing for column stores", bob, concept_vector(2))
  end

  def search(query, mode, **filters)
    open_rankings(**filters)
    fill_in "Search papers", with: query
    choose mode
    click_button "Search"
  end

  def ranked_names = all('[data-testid="university-name"]').map(&:text)

  it "ranks by topic in hybrid mode too" do
    stub_query_embedding("robot imitation" => concept_vector(0))
    search("robot imitation", "Both (hybrid)")

    expect(page).to have_css("h2", text: "Rankings for “robot imitation”")
    expect(ranked_names).to eq(["Northbridge University"])
  end

  it "keeps the area ranking for keyword searches" do
    search("column stores", "Keyword")

    expect(page).to have_css("h2", exact_text: "Rankings")
    expect(page).to have_no_css('[data-testid="ranking-topic"]')
    expect(ranked_names).to eq(["Southfield University", "Northbridge University"])
  end

  it "says so when no paper in the selected years is on the topic" do
    stub_query_embedding("robot imitation" => concept_vector(0))
    search("robot imitation", "Meaning (semantic)", from: 2016, to: 2017)

    expect(page).to have_text("No papers on this topic in the selected areas and years")
    expect(page).to have_no_text("No universities match these filters")
  end

  it "labels each professor's topic score in the faculty list" do
    stub_query_embedding("robot imitation" => concept_vector(0))
    search("robot imitation", "Meaning (semantic)")
    within('[data-testid="ranking-row"]', text: "Northbridge University") { click_button "Show faculty" }

    expect(page).to have_css('[data-testid="faculty-score"]', exact_text: "topic score 1.0")
  end

  it "does not explain the topic ranking on the saved view" do
    stub_query_embedding("robot imitation" => concept_vector(0))
    visit root_path(q: "robot imitation", mode: "semantic", view: "saved")

    expect(page).to have_css("h2", exact_text: "Saved institutions")
    expect(page).to have_no_css('[data-testid="ranking-topic"]')
  end

  it "shows the search text as text, never as HTML" do
    query = "<b>robots</b>"
    stub_query_embedding(query => concept_vector(0))
    search(query, "Meaning (semantic)")

    expect(page).to have_css("h2", text: "Rankings for “<b>robots</b>”")
    expect(page).to have_no_css("h2 b")
  end

  it "shows all of a professor's papers when the embedding service is down on the professor page" do
    allow(Paper).to receive(:query_embedding).and_raise(VoyageClient::Error, "service down")
    visit professor_path(bob, q: "column stores", mode: "semantic", from: 2024, to: 2024)

    expect(page).to have_no_css('[data-testid="professor-topic"]')
    expect(all('[data-testid="paper-title"]').map(&:text))
      .to contain_exactly("Query optimization for column stores", "Indexing for column stores")
    expect(page).to have_link("Back to rankings", href: /q=column\+stores/)
  end

  it "lists a professor's topic papers most relevant first" do
    store("Column store compression", bob, concept_vector(2, toward: 3, weight: 0.3))
    stub_query_embedding("column stores" => concept_vector(2))
    visit professor_path(bob, q: "column stores", mode: "semantic", from: 2024, to: 2024)

    expect(page).to have_css('[data-testid="professor-topic"]', text: "Papers on “column stores”")
    expect(all('[data-testid="paper-title"]').map(&:text).last).to eq("Column store compression")
  end
end
