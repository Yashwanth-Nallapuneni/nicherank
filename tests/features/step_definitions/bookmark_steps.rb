When("I save {string}") do |name|
  within(university_row(name)) { click_button "Save #{name}", exact: true }
end

When("I unsave {string}") do |name|
  within(university_row(name)) { click_button "Unsave #{name}", exact: true }
end

When("I open my saved institutions") do
  find('[data-saved-link]').click
  expect(page).to have_css("h2", exact_text: "Saved institutions")
end

When("I return to all institution rankings") do
  within('nav[aria-label="Institutions"]') { click_link "Rankings" }
end

When("I reload the bookmarks page") do
  page.refresh
end

When("I return from papers to my saved institutions") do
  click_link "Back to rankings"
  expect(page).to have_css("h2", exact_text: "Saved institutions")
end

Then("the saved institution count should be {int}") do |count|
  expect(page).to have_css('[data-saved-count]', exact_text: count.to_s)
end

Then("my visible saved institutions should be {string}") do |name|
  expect(page).to have_css('[data-testid="ranking-row"]', count: 1)
  expect(page).to have_css('[data-testid="university-name"]', exact_text: name)
end

Then("my saved list should have no visible institutions") do
  expect(page).to have_no_css('[data-testid="ranking-row"]')
end

Then("{string} should be marked as saved") do |name|
  expect(university_row(name)).to have_css('button[aria-pressed="true"]', text: "Saved")
end

Then("{string} should not be marked as saved") do |name|
  expect(university_row(name)).to have_button("Save #{name}", exact: true)
  expect(university_row(name)).to have_no_css('button[aria-pressed="true"]')
end

Given("the browser contains damaged bookmark data") do
  page.execute_script('window.localStorage.setItem("nicherank.savedInstitutions.v1", "{broken")')
end

Given("this browser refuses to store bookmarks") do
  page.execute_script('Storage.prototype.setItem = function() { throw new DOMException("Blocked", "SecurityError"); }')
end

When("I remove the saved institution in another tab") do
  original = current_window
  other = open_new_window
  within_window(other) do
    visit "/"
    click_button "Unsave Northbridge University", exact: true
  end
  other.close
  switch_to_window(original)
end

When("I go back to the previous bookmarks page") do
  page.go_back
  expect(page).to have_css("h2", exact_text: "Saved institutions")
end
