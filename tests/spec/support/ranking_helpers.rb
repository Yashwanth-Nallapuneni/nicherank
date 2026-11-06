# frozen_string_literal: true

# Shared UI setup for the acceptance drafts. Keep the tests/ folder together.
# Setup instructions are in tests/handoff.md.
# Always set filters explicitly so fixtures do not depend on the site's defaults.
module RankingHelpers
  def open_rankings(**filters)
    visit "/"
    apply_filters(**filters)
  end

  def apply_filters(areas: :all, from: 2022, to: 2024, location: "Worldwide")
    select_areas(areas)
    select from.to_s, from: "From year"
    select to.to_s, from: "To year"
    select location, from: "Country or region"
    click_button "Update rankings"
  end

  def select_areas(areas)
    within('[data-testid="research-area-filters"]') do
      check "All areas"
      unless areas == :all
        uncheck "All areas"
        areas.each { |area| check area }
      end
    end
  end
end
