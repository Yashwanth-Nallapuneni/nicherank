# frozen_string_literal: true

require "rails_helper"
require_relative "../support/ranking_helpers"

RSpec.describe "Search paging, counts and keeping the visitor's place", type: :feature do
  include RankingHelpers

  let!(:northbridge) { University.create!(openalex_id: "I940001", name: "Northbridge University") }
  let!(:lakeside) { University.create!(openalex_id: "I940002", name: "Lakeside University") }

  let!(:alice) do
    Professor.create!(openalex_id: "A940001", name: "Alice Researcher", title: "Professor",
                      university_id: northbridge.id, match_confidence: "manual")
  end

  let!(:ben) do
    Professor.create!(openalex_id: "A940002", name: "Ben Researcher", title: "Professor",
                      university_id: lakeside.id, match_confidence: "manual")
  end

  let!(:papers) do
    [
      ["W940001", "Graph learning one", alice, 2022, "NeurIPS"],
      ["W940002", "Graph learning two", alice, 2023, "NeurIPS"],
      ["W940003", "Graph learning three", alice, 2024, "NeurIPS"],
      ["W940004", "Query optimization", ben, 2024, "SIGMOD"]
    ].map do |openalex_id, title, author, year, venue|
      paper = Paper.create!(openalex_id: openalex_id, title: title, year: year, venue: venue,
                            paper_type: "conference-paper", venue_tier: "A*",
                            venue_tier_source: "core2023", citations: 0)
      Authorship.create!(professor_id: author.id, paper_id: paper.id)
      paper
    end
  end

  def search_for(keyword)
    fill_in "Search papers", with: keyword
    click_button "Search"
  end

  def result_titles
    all('[data-testid="paper-title"]').map(&:text)
  end

  def ranked_names
    all('[data-testid="university-name"]').map(&:text)
  end

  it "ticking one area while All areas is still checked shows only that area" do
    open_rankings
    expect(ranked_names).to contain_exactly("Northbridge University", "Lakeside University")

    within('[data-testid="research-area-filters"]') { check "Databases" }
    click_button "Update rankings"

    expect(ranked_names).to eq(["Lakeside University"])
    expect(page).to have_checked_field("Databases")
    expect(page).to have_unchecked_field("All areas")
  end

  it "keeps an expanded university open across a search and after viewing a professor" do
    open_rankings
    within(find('[data-testid="ranking-row"]', text: "Northbridge University")) { click_button "Show faculty" }
    expect(page).to have_css('[data-testid="faculty-row"]', text: "Alice Researcher")

    search_for "graph"
    expect(page).to have_css('[data-testid="paper-result"]', count: 3)
    expect(page).to have_css('[data-testid="faculty-row"]', text: "Alice Researcher")

    click_link "View papers"
    click_link "Back to rankings"
    expect(page).to have_css('[data-testid="faculty-row"]', text: "Alice Researcher")
  end

  it "says how many papers matched when there are more than one page" do
    stub_const("Paper::SEARCH_LIMIT", 2)
    open_rankings
    search_for "graph"

    expect(page).to have_css('[data-testid="paper-result"]', count: 2)
    expect(page).to have_content("Showing the top 2 of 3 matching papers")
  end

  it "shows a capped count as N+ for very broad searches" do
    stub_const("Paper::SEARCH_LIMIT", 1)
    stub_const("Paper::COUNT_CAP", 2)
    open_rankings
    search_for "graph"

    expect(page).to have_content("Showing the top 1 of 2+ matching papers")
  end

  it "pages through results with Next and Previous" do
    stub_const("Paper::SEARCH_LIMIT", 2)
    open_rankings
    search_for "graph"
    first_page = result_titles

    click_link "Next"
    expect(page).to have_content("Showing papers 3–3 of 3 matching papers")
    expect(result_titles.size).to eq(1)
    expect(result_titles & first_page).to be_empty

    click_link "Previous"
    expect(result_titles).to eq(first_page)
  end

  it "sends an out-of-range page number to the last page instead of failing" do
    stub_const("Paper::SEARCH_LIMIT", 2)
    visit "/?q=graph&page=99999999999999999999999"

    expect(page.status_code).to eq(200)
    expect(page).to have_content("Showing papers 3–3 of 3 matching papers")
  end

  it "sorts results by year, newest first" do
    open_rankings
    search_for "graph"
    select "Year (newest first)", from: "Sort by"
    click_button "Sort"

    expect(result_titles).to eq(["Graph learning three", "Graph learning two", "Graph learning one"])
  end
end
