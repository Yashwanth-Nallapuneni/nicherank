When("I sort institutions by {string}") do |order|
  select order, from: "Sort institutions"
  click_button "Update rankings"
end

Then("the institutions should appear in this order: {string}") do |names|
  expect(all('[data-testid="university-name"]').map(&:text)).to eq(names.split(", "))
end

Then("{string} should have ranking score {int}") do |name, score|
  expect(university_row(name).find('[data-testid="ranking-score"]').text.to_f).to eq(score)
end

When("I return to the institution rankings") do
  click_link "Back to rankings"
end

Then("institutions should still be sorted by {string}") do |order|
  expect(page).to have_select("Sort institutions", selected: order)
end

Then("I should see no university ranking rows") do
  expect(page).to have_no_css('[data-testid="ranking-row"]')
end
