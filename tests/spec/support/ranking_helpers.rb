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
    expect(page).to have_current_path(/from=#{from}.*to=#{to}/)
  end

  def select_areas(areas)
    if page.has_css?('[data-toggle-filters]', wait: 0) && !page.has_css?("#filter-panel", wait: 0)
      find('[data-toggle-filters]').click
    end
    within('[data-testid="research-area-filters"]') do
      check "All areas"
      unless areas == :all
        uncheck "All areas"
        areas.each do |area|
          all("details.area-group").each do |group|
            if group.has_css?("label", text: area, visible: :all, wait: 0) && !group.matches_css?("[open]")
              group.find("summary").click
            end
          end
          check area
        end
      end
    end
  end
end
