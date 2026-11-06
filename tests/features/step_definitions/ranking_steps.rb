# UI interactions and assertions mirror tests/spec/features/basic_rankings_spec.rb.
module RankingStepHelpers
  def university_row(name)
    find('[data-testid="ranking-row"]') do |row|
      row.has_css?('[data-testid="university-name"]', exact_text: name, count: 1, wait: 0)
    end
  end

  # "Northbridge" -> "Northbridge University"
  def full_university_name(short) = universities.keys.find { |name| name.split.first == short } || short

  def expect_ranked_universities(*names)
    within('[data-testid="rankings"]') do
      expect(page).to have_css('[data-testid="ranking-row"]', count: names.length)
      names.each { |name| expect(page).to have_css('[data-testid="university-name"]', exact_text: name) }
      expect(page).to have_css('[data-testid="university-name"]', count: names.length)
    end
  end

  def expect_areas_checked(*areas)
    within('[data-testid="research-area-filters"]') do
      areas.each { |area| expect(page).to have_checked_field(area) }
      expect(page).to have_checked_field(count: areas.length)
    end
  end
end
World(RankingStepHelpers)

Given(/^I (?:am viewing|view) worldwide rankings for all areas from (\d+) through (\d+)$/) do |from, to|
  @from, @to = from.to_s, to.to_s
  open_rankings(from: from.to_i, to: to.to_i)
end

Given("I am viewing rankings for only {string} from {int} through {int}") do |area, from, to|
  @from, @to = from.to_s, to.to_s
  open_rankings(areas: [area], from: from, to: to)
  expect(page).to have_checked_field(area)
end

When("I open NicheRank") do
  visit "/"
end

When("I select only {string} and update the rankings") do |area|
  select_areas([area])
  click_button "Update rankings"
end

When("I also select {string} and update the rankings") do |area|
  within('[data-testid="research-area-filters"]') { check area }
  click_button "Update rankings"
end

When("I change the year range to {int} through {int} and update the rankings") do |from, to|
  @from, @to = from.to_s, to.to_s
  select @from, from: "From year"
  select @to, from: "To year"
  click_button "Update rankings"
end

Then("I should see {string} at rank {int}") do |name, rank|
  within('[data-testid="rankings"]') do
    expect(university_row(name)).to have_css('[data-testid="rank"]', exact_text: rank.to_s)
  end
end

Then("{word} should appear above {word} with a higher ranking score") do |first, second|
  expected_names = [full_university_name(first), full_university_name(second)]
  within('[data-testid="rankings"]') do
    expect(page).to have_css('[data-testid="ranking-row"]', count: 2)
    names = all('[data-testid="university-name"]').map(&:text)
    scores = all('[data-testid="ranking-row"] [data-testid="ranking-score"]').map { |cell| Float(cell.text, exception: false) }
    expect(names).to eq(expected_names)
    expect(scores.all?(Float)).to be(true)
    expect(scores.first).to be > scores.last
  end
end

Then("I should see only {string} and {string} in the rankings") do |first, second|
  expect_ranked_universities(first, second)
end

Then("I should not see {string} in the rankings") do |name|
  within('[data-testid="rankings"]') do
    expect(page).to have_no_css('[data-testid="university-name"]', exact_text: name)
  end
end

Then("I should see all three universities in the rankings") do
  expect_ranked_universities(*universities.keys)
end

Then("both research areas should remain selected") do
  expect_areas_checked("Machine learning", "Databases")
end

Then("only {string} should remain selected") do |area|
  expect(page).to have_select("From year", selected: @from)
  expect(page).to have_select("To year", selected: @to)
  expect_areas_checked(area)
end

Then("I should see a search field labelled {string}") do |label|
  expect(page).to have_field(label)
end

When("I expand {string}") do |name|
  @expanded = name
  within(university_row(name)) { click_button "Show faculty" }
end

When("I collapse {string}") do |name|
  within(university_row(name)) { click_button "Hide faculty" }
end

Then("its faculty list should contain only {string} and {string}") do |first, second|
  within(university_row(@expanded)) do
    within('[data-testid="faculty-list"]') do
      expect(page).to have_css('[data-testid="faculty-row"]', count: 2)
      expect(page).to have_css('[data-testid="faculty-name"]', count: 2)
      [first, second].each do |name|
        expect(page).to have_css('[data-testid="faculty-name"]', exact_text: name, count: 1)
      end
    end
  end
end

Then("its faculty list should be hidden") do
  expect(university_row(@expanded)).to have_no_css('[data-testid="faculty-list"]')
end

Then("{string} should still appear in the rankings") do |name|
  expect(university_row(name)).to be_present
  expect_ranked_universities(*universities.keys)
end

Then(/^(.+)'s name should link to "([^"]*)"$/) do |name, url|
  within(university_row(@expanded)) { expect(page).to have_link(name, href: url) }
end

When(/^I expand "([^"]*)" and view (.+)'s papers$/) do |university, professor|
  step %(I expand "#{university}")
  @viewed_professor = professor
  within(university_row(university)) do
    expect(page).to have_css('[data-testid="faculty-row"]', count: 1)
    within('[data-testid="faculty-row"]', text: professor) { click_link "View papers" }
  end
  expect(page).to have_css("h1", exact_text: professor)
end

Then("I should see exactly these papers with their years and venues:") do |table|
  within('[data-testid="professor-papers"]') do
    expect(page).to have_css('[data-testid="professor-paper"]', count: table.hashes.length)
    table.hashes.each do |row|
      within('[data-testid="professor-paper"]', text: row["title"]) do
        expect(page).to have_css('[data-testid="paper-title"]', exact_text: row["title"])
        expect(page).to have_css('[data-testid="paper-year"]', exact_text: row["year"])
        expect(page).to have_css('[data-testid="paper-venue"]', exact_text: row["venue"])
      end
    end
  end
end

Then(/^I should not see "([^"]*)" or another professor's papers in that list$/) do |title|
  others = Paper.joins(:authorships).where.not(authorships: { professor_id: professors.fetch(@viewed_professor).id }).pluck(:title)
  within('[data-testid="professor-papers"]') do
    ([title] + others).each { |t| expect(page).to have_no_css('[data-testid="paper-title"]', exact_text: t) }
  end
end

Then("I should not see {string} because it is outside the selected research area") do |title|
  within('[data-testid="professor-papers"]') do
    expect(page).to have_no_css('[data-testid="paper-title"]', exact_text: title)
  end
end
