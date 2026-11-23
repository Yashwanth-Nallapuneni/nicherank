require "rails_helper"

RSpec.describe "Saved institution navigation", type: :feature do
  before do
    stub_const("Paper::SEARCH_LIMIT", 1)
    university = University.create!(openalex_id: "I970001", name: "Example University")
    professor = Professor.create!(openalex_id: "A970001", name: "Alice", university: university,
                                  title: "Professor", match_confidence: "manual")
    2.times do |number|
      paper = Paper.create!(openalex_id: "W97000#{number}", title: "Graph paper #{number}",
                            year: 2024, venue: "NeurIPS", paper_type: "conference-paper")
      Authorship.create!(professor: professor, paper: paper)
    end
  end

  it "carries the saved view through search sorting, pagination, clearing and filters" do
    visit "/?view=saved&q=graph&from=2022&to=2024"
    expect(page).to have_css("h2", exact_text: "Saved institutions")
    select "Year (newest first)", from: "Sort by"
    click_button "Sort"
    click_link "Next"
    expect(page).to have_css("h2", exact_text: "Saved institutions")
    expect(page).to have_field("Search papers", with: "graph")
    click_button "Clear search"
    expect(page).to have_css("h2", exact_text: "Saved institutions")
    select "2023", from: "From year"
    click_button "Update rankings"
    expect(page).to have_css("h2", exact_text: "Saved institutions")
    expect(page).to have_select("From year", selected: "2023")
  end
end
