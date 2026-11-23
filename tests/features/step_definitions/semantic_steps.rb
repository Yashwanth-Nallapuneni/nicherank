# Search by meaning. Each paper gets a hand-made embedding along a numbered "concept";
# the embedding API is stubbed so no scenario calls Voyage.

Given("the following papers are stored with embeddings:") do |table|
  table.hashes.each do |row|
    paper = store_paper(title: row["title"])
    add_author(professors.values.first, paper) if professors.any?
    embed_paper!(paper, concept_vector(row["concept"].to_i))
  end
end

Given("the embedding service places {string} at concept {int}") do |query, concept|
  (@query_vectors ||= {})[query] = concept_vector(concept)
  stub_query_embedding(@query_vectors)
end

Given("the embedding service is down") do
  allow(Paper).to receive(:query_embedding).and_raise(VoyageClient::Error, "service down")
end

When("I search by {string} for {string}") do |mode, query|
  fill_in "Search papers", with: query
  choose mode
  click_button "Search"
end

Then("{string} should be the first search result") do |title|
  expect(first('[data-testid="paper-title"]').text).to eq(title)
end
