require "rails_helper"
require_relative "../support/ranking_helpers"

RSpec.describe "Institution sorting", type: :feature do
  include RankingHelpers

  before do
    stub_const("Paper::SEARCH_LIMIT", 1)
    ["Zebra University", "Alpha University"].each_with_index do |name, index|
      university = University.create!(openalex_id: "I96000#{index}", name: name)
      professor = Professor.create!(openalex_id: "A96000#{index}", name: "Researcher #{index}",
                                    university: university, title: "Professor", match_confidence: "manual")
      (2 - index).times do |number|
        paper = Paper.create!(openalex_id: "W9600#{index}#{number}", title: "Graph learning #{index} #{number}",
                              year: 2022 + number, venue: "NeurIPS", paper_type: "conference-paper")
        Authorship.create!(professor: professor, paper: paper)
      end
    end
  end

  def names = all('[data-testid="university-name"]').map(&:text)

  it "keeps institution sorting separate from paper sorting and pagination" do
    open_rankings(areas: ["Machine learning"])
    fill_in "Search papers", with: "graph"
    click_button "Search"
    select "Year (newest first)", from: "Sort by"
    click_button "Sort"

    select "Lowest score", from: "Sort institutions"
    click_button "Update rankings"
    expect(names).to eq(["Alpha University", "Zebra University"])
    expect(page).to have_select("Sort by", selected: "Year (newest first)")
    expect(page).to have_checked_field("Machine learning")
    expect(page).to have_field("Search papers", with: "graph")

    click_link "Next"
    expect(page).to have_select("Sort institutions", selected: "Lowest score")
    select "Relevance", from: "Sort by"
    click_button "Sort"
    expect(names).to eq(["Alpha University", "Zebra University"])
    click_button "Clear search"
    expect(page).to have_select("Sort institutions", selected: "Lowest score")
    expect(names).to eq(["Alpha University", "Zebra University"])
  end
end
