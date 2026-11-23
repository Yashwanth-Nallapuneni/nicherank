# frozen_string_literal: true

require "rails_helper"
require_relative "../support/ranking_helpers"
require_relative "../support/embedding_helpers"

# Meaning and hybrid results list each work once (Paper.collapse_versions).
RSpec.describe "Semantic search results", type: :feature do
  include RankingHelpers
  include EmbeddingHelpers

  let!(:uni) { University.create!(openalex_id: "I990001", name: "Northbridge University") }
  let!(:alice) do
    Professor.create!(openalex_id: "A990001", name: "Alice Researcher", title: "Professor",
                      university_id: uni.id, match_confidence: "manual")
  end

  def store(openalex_id, title, vector, type: "conference-paper", year: 2024)
    paper = Paper.create!(openalex_id: openalex_id, title: title, year: year, venue: "NeurIPS", paper_type: type,
                          venue_tier: ("A*" unless type == "preprint"), venue_tier_source: ("core2023" unless type == "preprint"), citations: 0)
    Authorship.create!(professor_id: alice.id, paper_id: paper.id)
    embed_paper!(paper, vector)
    paper
  end

  before do
    # The preprint sits slightly closer to the query than its published version, as often happens.
    store("W990001", "Imitation learning from human video", concept_vector(0, toward: 1, weight: 0.1), year: 2024)
    store("W990002", "Imitation Learning from Human Video", concept_vector(0), type: "preprint", year: 2023)
    store("W990003", "Query optimization for column stores", concept_vector(2))
    stub_query_embedding("teaching robots by showing them" => concept_vector(0))
  end

  def search(query, mode)
    open_rankings
    fill_in "Search papers", with: query
    choose mode
    click_button "Search"
  end

  def titles = all('[data-testid="paper-title"]').map(&:text)

  it "lists a work once, in its published version, and names the version it left out" do
    search("teaching robots by showing them", "Meaning (semantic)")

    expect(titles).to eq(["Imitation learning from human video", "Query optimization for column stores"])
    within(first('[data-testid="paper-result"]')) do
      expect(page).to have_css('[data-testid="other-versions"]', exact_text: "Also listed as preprint (2023)")
    end
    expect(page).to have_css('[data-testid="other-versions"]', count: 1)
  end

  it "counts works, not copies" do
    stub_const("Paper::SEARCH_LIMIT", 1)
    search("teaching robots by showing them", "Meaning (semantic)")

    expect(page).to have_text("Showing the top 1 of 2 closest papers")
  end

  it "lists each work once in hybrid mode too" do
    search("teaching robots by showing them", "Both (hybrid)")

    expect(titles.count { |t| t.casecmp?("Imitation learning from human video") }).to eq(1)
  end

  it "leaves keyword results unchanged" do
    search("imitation learning", "Keyword")

    expect(titles).to contain_exactly("Imitation learning from human video", "Imitation Learning from Human Video")
    expect(page).to have_no_css('[data-testid="other-versions"]')
  end
end
