# frozen_string_literal: true

# Draft tests for the team's Rails app; no feature implementation is supplied.
# Keep tests/ together; setup and remaining work are in tests/handoff.md.
# Prerequisites are the same as
# nicherank_spec.rb: Rails/RSpec/Capybara, the existing ActiveRecord models,
# an isolated PostgreSQL test database, and cleanup between examples.
# Configure a JavaScript-capable Capybara driver if the controls need JavaScript.
#
# Proposed UI contract; adapt labels and selectors to the team's design:
# - / has From year and To year selects, a Country or region select (Worldwide
#   by default), and an Update rankings button.
# - [data-testid="research-area-filters"] has All areas and individual area
#   checkboxes. All areas selects/deselects every research area.
# - Ranking rows retain the selectors in nicherank_spec.rb and add a numeric
#   [data-testid="ranking-score"]. A row contains Show faculty/Hide faculty
#   buttons and a [data-testid="faculty-list"] with [data-testid="faculty-row"]
#   entries. [data-testid="faculty-name"] holds each professor's name/link.
# - Each faculty row has a View papers link. The resulting view has the
#   professor's name as a heading and [data-testid="professor-papers"] holding
#   [data-testid="professor-paper"] rows with paper-title, paper-year and
#   paper-venue data-testid elements. It preserves the selected areas/years.
# - Empty rankings show "No universities match these filters" and no rows.
#
# Fixture contract: NeurIPS maps to Machine learning and SIGMOD to Databases.
# These synthetic publications are qualifying, single-author papers. Tests
# check relative scores/order; they do not define the full ranking formula.
# Real CSRankings eligibility and author-credit parity need additional source
# metadata beyond the current schema. Area mapping is also backend-owned;
# the broad papers.field value alone is not a CSRankings research area.
#
# LOCATION DEPENDENCY: the location context proposes University#country_code
# (US/CA/GB). This attribute is absent from the frozen schema. The backend must
# supply institution country metadata and a country-to-region mapping, then
# adapt that fixture setup to its chosen storage. No schema change is made here.
# These examples are not silently skipped when that dependency is missing.
#
# References for the intended browsing behavior and score interpretation:
# https://csrankings.org/
# https://csrankings.org/faq.html
# From the Rails root after setup:
# bundle exec rspec -I tests/spec tests/spec/features/basic_rankings_spec.rb

require "rails_helper"
require_relative "../support/ranking_helpers"

RSpec.describe "Basic university ranking stories", type: :feature do
  include RankingHelpers

  let!(:universities) do
    {
      northbridge: University.create!(openalex_id: "I910001", name: "Northbridge University"),
      lakeside: University.create!(openalex_id: "I910002", name: "Lakeside University"),
      harbor: University.create!(openalex_id: "I910003", name: "Harbor University")
    }
  end

  let!(:professors) do
    [
      [:alice, "A910001", "Alice Researcher", :northbridge],
      [:dana, "A910002", "Dana Researcher", :northbridge],
      [:ben, "A910003", "Ben Researcher", :lakeside],
      [:cara, "A910004", "Cara Researcher", :harbor]
    ].each_with_object({}) do |(key, openalex_id, name, university), records|
      records[key] = Professor.create!(
        openalex_id: openalex_id, name: name, title: "Professor",
        university_id: universities.fetch(university).id,
        homepage_url: "https://example.org/#{key}", match_confidence: "manual"
      )
    end
  end

  let!(:papers) do
    [
      ["W910001", "Neural baselines", :alice, 2019, "NeurIPS"],
      ["W910002", "Neural methods", :alice, 2022, "NeurIPS"],
      ["W910003", "Neural models", :alice, 2024, "NeurIPS"],
      ["W910004", "Reliable queries", :dana, 2024, "SIGMOD"],
      ["W910005", "Learning representations", :ben, 2023, "NeurIPS"],
      ["W910006", "Future learning", :ben, 2025, "NeurIPS"],
      ["W910007", "Database indexing", :cara, 2023, "SIGMOD"],
      ["W910008", "Query planning", :alice, 2024, "SIGMOD"]
    ].map do |openalex_id, title, author, year, venue|
      paper = Paper.create!(
        openalex_id: openalex_id, title: title, year: year, venue: venue,
        paper_type: "conference-paper", venue_tier: "A*",
        venue_tier_source: "core2023", citations: 0
      )
      Authorship.create!(professor_id: professors.fetch(author).id, paper_id: paper.id)
      paper
    end
  end

  def university_row(key)
    find('[data-testid="ranking-row"]') do |row|
      row.has_css?(
        '[data-testid="university-name"]',
        exact_text: universities.fetch(key).name, count: 1, wait: 0
      )
    end
  end

  def expect_ranked_universities(*keys)
    within('[data-testid="rankings"]') do
      expect(page).to have_css('[data-testid="ranking-row"]', count: keys.length)
      keys.each do |key|
        expect(page).to have_css(
          '[data-testid="university-name"]', exact_text: universities.fetch(key).name
        )
      end
      expect(page).to have_css('[data-testid="university-name"]', count: keys.length)
    end
  end

  def expect_rank_order(first, second)
    within('[data-testid="rankings"]') do
      expect(page).to have_css('[data-testid="ranking-row"]', count: 2)
      expect(university_row(first)).to have_css('[data-testid="rank"]', exact_text: "1")
      expect(university_row(second)).to have_css('[data-testid="rank"]', exact_text: "2")
    end

    expected_names = [universities.fetch(first).name, universities.fetch(second).name]
    expect(page).to have_css('[data-testid="rankings"]') do |rankings|
      names = rankings.all('[data-testid="university-name"]', wait: 0).map(&:text)
      scores = rankings.all('[data-testid="ranking-row"] [data-testid="ranking-score"]', wait: 0).map do |cell|
        Float(cell.text, exception: false)
      end
      names == expected_names && scores.length == 2 && scores.all? && scores.first > scores.last
    end
  end

  def expand_northbridge
    within(university_row(:northbridge)) { click_button "Show faculty" }
  end

  it "shows universities in rank order with their scores (story 1)" do
    open_rankings(areas: ["Machine learning"])

    expect_rank_order(:northbridge, :lakeside)
  end

  { "Machine learning" => :lakeside, "Databases" => :harbor }.each do |area, other|
    it "limits rankings to universities publishing in #{area} (story 6)" do
      open_rankings
      expect_ranked_universities(:northbridge, :lakeside, :harbor)

      select_areas([area])
      click_button "Update rankings"

      expect_ranked_universities(:northbridge, other)
    end
  end

  it "lets a visitor select multiple research areas (story 6)" do
    open_rankings(areas: ["Machine learning"])
    expect_ranked_universities(:northbridge, :lakeside)

    within('[data-testid="research-area-filters"]') { check "Databases" }
    click_button "Update rankings"

    expect_ranked_universities(:northbridge, :lakeside, :harbor)
    expect(page).to have_checked_field("Machine learning")
    expect(page).to have_checked_field("Databases")
  end

  it "updates rankings for an inclusive year range and keeps the selected area (story 7)" do
    open_rankings(areas: ["Machine learning"])
    expect_rank_order(:northbridge, :lakeside)

    select "2023", from: "From year"
    select "2025", from: "To year"
    click_button "Update rankings"

    expect_rank_order(:lakeside, :northbridge)
    expect(page).to have_select("From year", selected: "2023")
    expect(page).to have_select("To year", selected: "2025")
    within('[data-testid="research-area-filters"]') do
      expect(page).to have_checked_field("Machine learning")
      expect(page).to have_unchecked_field("Databases")
      expect(page).to have_checked_field(count: 1)
    end
  end

  context "with institution country metadata", :requires_location_metadata do
    before do
      # Proposed fixture interface, not a field in the delivered schema.
      unless universities.values.all? { |university| university.has_attribute?(:country_code) }
        raise NotImplementedError,
          "Wire the country fixtures to the team's location metadata before running story 8. " \
          "The delivered universities table has no country_code attribute."
      end

      { northbridge: "US", lakeside: "CA", harbor: "GB" }.each do |key, country|
        universities.fetch(key).update!(country_code: country)
      end
    end

    it "filters universities by country (story 8)" do
      open_rankings
      expect_ranked_universities(:northbridge, :lakeside, :harbor)

      select "Canada", from: "Country or region"
      click_button "Update rankings"

      expect_ranked_universities(:lakeside)
    end

    it "includes countries in the selected region and excludes others (story 8)" do
      open_rankings
      expect_ranked_universities(:northbridge, :lakeside, :harbor)

      select "North America", from: "Country or region"
      click_button "Update rankings"

      expect_ranked_universities(:northbridge, :lakeside)
    end

    it "combines country and area filters and explains an empty ranking (story 8)" do
      open_rankings(areas: ["Databases"])
      expect_ranked_universities(:northbridge, :harbor)

      select "Canada", from: "Country or region"
      click_button "Update rankings"

      expect(page).to have_text("No universities match these filters")
      within('[data-testid="rankings"]') do
        expect(page).to have_no_css('[data-testid="ranking-row"]')
      end
      expect(page).to have_checked_field("Databases")
      expect(page).to have_unchecked_field("Machine learning")
      expect(page).to have_select("Country or region", selected: "Canada")
      expect(page).to have_select("From year", selected: "2022")
      expect(page).to have_select("To year", selected: "2024")
    end
  end

  it "expands and collapses the selected university's faculty (story 9)" do
    open_rankings
    expect(university_row(:northbridge)).to have_no_css('[data-testid="faculty-list"]')

    expand_northbridge

    within(university_row(:northbridge)) do
      within('[data-testid="faculty-list"]') do
        expect(page).to have_css('[data-testid="faculty-row"]', count: 2)
        expect(page).to have_css('[data-testid="faculty-name"]', count: 2)
        [:alice, :dana].each do |key|
          expect(page).to have_css(
            '[data-testid="faculty-name"]', exact_text: professors.fetch(key).name, count: 1
          )
        end
      end
      click_button "Hide faculty"
    end
    expect(university_row(:northbridge)).to have_no_css('[data-testid="faculty-list"]')
    expect_ranked_universities(:northbridge, :lakeside, :harbor)
  end

  it "links a professor's name to their website (story 10)" do
    open_rankings
    expand_northbridge

    within(university_row(:northbridge)) do
      # Check the target; loading a third-party website is outside this test.
      expect(page).to have_link(
        professors.fetch(:alice).name, href: professors.fetch(:alice).homepage_url
      )
    end
  end

  it "shows a professor's papers within the selected areas and years (story 11)" do
    open_rankings(areas: ["Machine learning"])
    expand_northbridge

    within(university_row(:northbridge)) do
      expect(page).to have_css('[data-testid="faculty-row"]', count: 1)
      within('[data-testid="faculty-row"]', text: professors.fetch(:alice).name) do
        click_link "View papers"
      end
    end

    expect(page).to have_css("h1", exact_text: professors.fetch(:alice).name)
    within('[data-testid="professor-papers"]') do
      expect(page).to have_css('[data-testid="professor-paper"]', count: 2)
      { "Neural methods" => 2022, "Neural models" => 2024 }.each do |title, year|
        within('[data-testid="professor-paper"]', text: title) do
          expect(page).to have_css('[data-testid="paper-title"]', exact_text: title)
          expect(page).to have_css('[data-testid="paper-year"]', exact_text: year.to_s)
          expect(page).to have_css('[data-testid="paper-venue"]', exact_text: "NeurIPS")
        end
      end
      expect(page).to have_no_css('[data-testid="paper-title"]', exact_text: "Neural baselines")
      expect(page).to have_no_css('[data-testid="paper-title"]', exact_text: "Query planning")
    end
  end
end
