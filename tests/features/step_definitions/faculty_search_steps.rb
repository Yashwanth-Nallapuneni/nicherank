Given("these faculty research profiles are available:") do |table|
  table.hashes.each do |row|
    vector = concept_vector(row["concept"].to_i)
    ProfessorEmbedding.create!(professor: professors.fetch(row["professor"]),
                               embedding: "[#{vector.join(',')}]", papers: row["publications"].to_i)
  end
end

Given("faculty results show one profile per page") { stub_const("ProfessorEmbedding::PAGE_SIZE", 1) }

When("I open the faculty finder") do
  visit faculty_path
end

When("I find faculty for {string}") do |topic|
  fill_in "Research topic", with: topic
  click_button "Find faculty"
end

When("I narrow faculty results to {string}") do |school|
  select school, from: "Institution"
  click_button "Find faculty"
end

When("I open the first faculty match and return") do
  first('[data-testid="faculty-result"] h3 a').click
  expect(page).to have_css('[data-testid="professor-papers"]')
  click_link "Back to faculty results"
end

When("I open the next faculty page") { click_link "Next" }
When("I clear the faculty search") { click_link "Clear" }

Then("{string} should be the first faculty match") do |name|
  expect(first('[data-testid="faculty-result"] h3').text).to eq(name)
end

Then(/^I should see (\d+) faculty match(?:es)?$/) do |count|
  expect(page).to have_css('[data-testid="faculty-result"]', count: count.to_i)
end

Then("the faculty search should keep {string} at {string}") do |topic, school|
  expect(page).to have_field("Research topic", with: topic)
  expect(page).to have_select("Institution", selected: school)
end
