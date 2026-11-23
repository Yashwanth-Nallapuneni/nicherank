# Each work listed once in meaning results (Paper.collapse_versions).

Given("{string} is also stored as a {int} preprint") do |title, year|
  original = papers.fetch(title)
  copy = store_paper(title: title, year: year, paper_type: "preprint", venue_tier: nil, venue_tier_source: nil)
  original.professors.each { |professor| add_author(professor, copy) }
  embed_paper!(copy, PaperEmbedding.find(original.id).embedding.delete("[]").split(",").map(&:to_f))
end

Then("{string} should appear once in the results") do |title|
  expect(all('[data-testid="paper-title"]').count { |node| node.text.casecmp?(title) }).to eq(1)
end
