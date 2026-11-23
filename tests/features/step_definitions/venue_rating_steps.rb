Given("these venue ratings are available:") do |table|
  table.hashes.each { |row| VenueRating.create!(row.merge("match_method" => "exact_title")) }
end

Given("a learning journal paper has ERA and SCImago ratings") do
  publication = store_paper(title: "Learning in a journal", venue: "Research Journal", paper_type: "article")
  add_author(professors.values.first, publication)
  [["era2010", "B"], ["scimago2025", "Q1"]].each do |source, grade|
    VenueRating.create!(venue: publication.venue, kind: "journal", source: source, ranking: grade, match_method: "exact_title")
  end
end

When("I choose the venue rating {string}") do |label|
  select label, from: "Venue rating"
  click_button "Update rankings"
end

When("I sort the rated papers and browse their professor") do
  select "Year (newest first)", from: "Sort by"
  click_button "Sort"
  expect(page).to have_select("Venue rating", selected: "ICORE 2026 · A*")
  click_button "Show faculty"
  click_link "View papers"
end

When("I open the saved version of these rated rankings") do
  visit find('[data-saved-link]', visible: :all)[:href]
end

Then("the venue rating selection should be {string}") do |label|
  expect(page).to have_select("Venue rating", selected: label)
end

When("I follow {string}") { |label| click_link label }
