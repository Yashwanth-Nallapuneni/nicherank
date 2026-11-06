# frozen_string_literal: true

# Draft acceptance tests; keep the tests/ folder together in the Rails app.
# See tests/handoff.md for setup and implementation work. No app code is included.
#
# Prerequisites supplied by that app:
# - rails_helper with rspec-rails, capybara/rails and capybara/rspec configured.
# - An isolated PostgreSQL test database with the schema in
#   data/db/postgres/schema.sql and transactional cleanup between examples.
# - University, Professor, Paper and Authorship ActiveRecord models.
# - A JavaScript-capable Capybara driver if the controls need JavaScript.
#
# Proposed UI contract (adapt these selectors/labels to the agreed design):
# - The rankings page is /, with a field labelled "Search papers" and buttons
#   labelled "Search" and "Clear search".
# - [data-testid="rankings"] contains [data-testid="ranking-row"] elements,
#   each with rank, university-name and numeric ranking-score data-testid cells.
# - The filter controls described in basic_rankings_spec.rb. Every example
#   selects all areas, worldwide, for 2024 instead of relying on default years.
# - [data-testid="paper-results"] contains [data-testid="paper-result"]
#   elements, each with [data-testid="paper-title"] and one
#   [data-testid="paper-author"] per author/university pair.
# - A search with no matches shows "No papers found" and zero result rows.
# - Clearing a search restores the initial rankings and removes paper results.
#
# Search covers title, abstract, keywords and primary_topic, matching SCHEMA.md.
# Paper ordering and the university ranking formula are outside this small set.
# The ranking example uses one school to avoid inventing a scoring formula.
# See basic_rankings_spec.rb for comparisons, filters, faculty and publications.
#
# From the Rails root after setup:
# bundle exec rspec -I tests/spec tests/spec/features/nicherank_spec.rb
# Capybara/RSpec reference:
# https://github.com/teamcapybara/capybara#using-capybara-with-rspec

require "rails_helper"
require_relative "../support/ranking_helpers"

RSpec.describe "Paper search and the rankings entry point", type: :feature do
  include RankingHelpers

  let!(:northbridge) do
    University.create!(openalex_id: "I900001", name: "Northbridge University")
  end

  let!(:alice) do
    Professor.create!(
      openalex_id: "A900001",
      name: "Alice Researcher",
      title: "Professor",
      match_confidence: "manual",
      university_id: northbridge.id
    )
  end

  let!(:title_match) do
    store_paper(openalex_id: "W900001", title: "Graph neural networks")
  end

  def store_paper(attributes)
    paper = Paper.create!({
      year: 2024,
      paper_type: "conference-paper",
      venue: "NeurIPS",
      venue_tier: "A*",
      venue_tier_source: "core2023",
      citations: 0,
      abstract: nil,
      keywords: nil,
      primary_topic: nil
    }.merge(attributes))
    Authorship.create!(professor_id: alice.id, paper_id: paper.id)
    paper
  end

  def search_for(keyword)
    fill_in "Search papers", with: keyword
    click_button "Search"
  end

  def ranking_snapshot(container)
    container.all('[data-testid="ranking-row"]', wait: 0).map do |row|
      {
        rank: Integer(row.find('[data-testid="rank"]').text, exception: false),
        university: row.find('[data-testid="university-name"]').text,
        score: Float(row.find('[data-testid="ranking-score"]').text, exception: false)
      }
    end
  end

  it "lets a visitor see university rankings and a search field (story 1)" do
    open_rankings(from: 2024, to: 2024)

    within('[data-testid="rankings"]') do
      expect(page).to have_css('[data-testid="ranking-row"]', count: 1)
      within('[data-testid="ranking-row"]') do
        expect(page).to have_css('[data-testid="rank"]', exact_text: "1")
        expect(page).to have_css(
          '[data-testid="university-name"]', exact_text: northbridge.name
        )
      end
    end
    expect(page).to have_field("Search papers")
  end

  context "with papers to search" do
    let!(:abstract_match) do
      store_paper(
        openalex_id: "W900002",
        title: "Learning representations",
        abstract: "A study of neural architectures"
      )
    end

    let!(:keyword_match) do
      store_paper(
        openalex_id: "W900003",
        title: "Model compression",
        keywords: "neural; compression"
      )
    end

    let!(:topic_match) do
      store_paper(
        openalex_id: "W900004",
        title: "Sequence prediction",
        primary_topic: "Neural computation"
      )
    end

    let!(:unrelated_paper) do
      store_paper(openalex_id: "W900005", title: "Reliable database transactions")
    end

    let!(:lakeside) do
      University.create!(openalex_id: "I900002", name: "Lakeside University")
    end

    let!(:ben) do
      Professor.create!(
        openalex_id: "A900002",
        name: "Ben Researcher",
        title: "Professor",
        match_confidence: "manual",
        university_id: lakeside.id
      )
    end

    before do
      Authorship.create!(professor_id: ben.id, paper_id: title_match.id)
      open_rankings(from: 2024, to: 2024)
    end

    ["neural", "NEURAL"].each do |keyword|
      it "finds only matching papers once each for #{keyword.inspect} (story 2)" do
        search_for(keyword)

        within('[data-testid="paper-results"]') do
          expect(page).to have_css('[data-testid="paper-result"]', count: 4)
          [title_match, abstract_match, keyword_match, topic_match].each do |paper|
            expect(page).to have_css('[data-testid="paper-result"]', count: 1) do |result|
              titles = result.all('[data-testid="paper-title"]', wait: 0).map(&:text)
              titles == [paper.title]
            end
          end
          expect(page).to have_no_css(
            '[data-testid="paper-title"]', exact_text: unrelated_paper.title
          )
        end
      end
    end

    it "shows each matching paper's authors and universities (story 3)" do
      search_for("networks")

      within('[data-testid="paper-results"]') do
        expect(page).to have_css('[data-testid="paper-result"]', count: 1)
        within('[data-testid="paper-result"]') do
          expect(page).to have_css(
            '[data-testid="paper-title"]', exact_text: title_match.title
          )
          expect(page).to have_css('[data-testid="paper-author"]', count: 2)
          within('[data-testid="paper-author"]', text: alice.name) do
            expect(page).to have_text(northbridge.name)
          end
          within('[data-testid="paper-author"]', text: ben.name) do
            expect(page).to have_text(lakeside.name)
          end
        end
      end
    end

    it "explains when nothing matches and removes previous results (story 4)" do
      search_for("neural")
      expect(page).to have_css('[data-testid="paper-result"]', count: 4)

      search_for("volcanology")

      expect(page).to have_text("No papers found")
      expect(page).to have_no_css('[data-testid="paper-result"]')
    end

    { "neural" => 4, "volcanology" => 0 }.each do |keyword, result_count|
      it "clears #{keyword.inspect} and restores the original rankings (story 5)" do
        expect(page).to have_css('[data-testid="ranking-row"]', count: 2)
        expect(page).to have_css('[data-testid="rank"]', text: /\A\d+\z/, count: 2)
        expect(page).to have_css(
          '[data-testid="ranking-score"]', text: /\A\d+(?:\.\d+)?\z/, count: 2
        )
        original_rankings = ranking_snapshot(find('[data-testid="rankings"]'))
        search_for(keyword)
        expect(page).to have_text("No papers found") if result_count.zero?
        expect(page).to have_css('[data-testid="paper-result"]', count: result_count)

        click_button "Clear search"

        expect(page).to have_field("Search papers", with: "")
        expect(page).to have_css('[data-testid="rankings"]') do |rankings|
          ranking_snapshot(rankings) == original_rankings
        end
        expect(page).to have_select("From year", selected: "2024")
        expect(page).to have_select("To year", selected: "2024")
        expect(page).to have_select("Country or region", selected: "Worldwide")
        expect(page).to have_checked_field("All areas")
        expect(page).to have_no_css('[data-testid="paper-result"]')
        expect(page).to have_no_text("No papers found")
      end
    end
  end
end
