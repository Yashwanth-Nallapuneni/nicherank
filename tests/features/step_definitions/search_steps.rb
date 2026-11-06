# UI interactions and assertions mirror tests/spec/features/nicherank_spec.rb.
module SearchStepHelpers
  def ranking_snapshot
    find('[data-testid="rankings"]').all('[data-testid="ranking-row"]', wait: 0).map do |row|
      {
        rank: Integer(row.find('[data-testid="rank"]').text, exception: false),
        university: row.find('[data-testid="university-name"]').text,
        score: Float(row.find('[data-testid="ranking-score"]').text, exception: false)
      }
    end
  end

  def search_for(keyword)
    fill_in "Search papers", with: keyword
    click_button "Search"
  end
end
World(SearchStepHelpers)

Given("I have searched for {string}") do |keyword|
  @rankings_before_search = ranking_snapshot
  expect(@rankings_before_search).not_to be_empty
  expect(@rankings_before_search.map { |row| row[:score] }.all?(Float)).to be(true)
  search_for(keyword)
end

When("I search for {string}") do |keyword|
  search_for(keyword)
end

When("I press {string}") do |button|
  click_button button
end

Then("I should see exactly these papers in the search results, each once:") do |table|
  titles = table.hashes.map { |row| row["title"] }
  within('[data-testid="paper-results"]') do
    expect(page).to have_css('[data-testid="paper-result"]', count: titles.length)
    titles.each do |title|
      expect(page).to have_css('[data-testid="paper-result"]', count: 1) do |result|
        result.all('[data-testid="paper-title"]', wait: 0).map(&:text) == [title]
      end
    end
  end
end

Then("I should not see {string} in the search results") do |title|
  within('[data-testid="paper-results"]') do
    expect(page).to have_no_css('[data-testid="paper-title"]', exact_text: title)
  end
end

Then("I should see exactly one result for {string}") do |title|
  within('[data-testid="paper-results"]') do
    expect(page).to have_css('[data-testid="paper-result"]', count: 1)
    expect(page).to have_css('[data-testid="paper-title"]', exact_text: title, count: 1)
  end
end

Then("that result should list these authors and their universities:") do |table|
  within('[data-testid="paper-result"]') do
    expect(page).to have_css('[data-testid="paper-author"]', count: table.hashes.length)
    table.hashes.each do |row|
      within('[data-testid="paper-author"]', text: row["author"]) { expect(page).to have_text(row["university"]) }
    end
  end
end

Then("I should see {string}") do |text|
  expect(page).to have_text(text)
end

Then("I should not see {string}") do |text|
  expect(page).to have_no_text(text)
end

Then("I should see no paper results") do
  expect(page).to have_no_css('[data-testid="paper-result"]')
end

Then("the {string} field should be empty") do |label|
  expect(page).to have_field(label, with: "")
end

Then("I should see the same university rankings as before the search") do
  expect(ranking_snapshot).to eq(@rankings_before_search)
end

Then("my research area, year and location filters should be unchanged") do
  expect(page).to have_select("From year", selected: @from)
  expect(page).to have_select("To year", selected: @to)
  expect(page).to have_select("Country or region", selected: "Worldwide")
  expect(page).to have_checked_field("All areas")
end
