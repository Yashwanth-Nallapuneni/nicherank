# Rank universities by a search topic. Papers get hand-made embeddings along a numbered "concept";
# the embedding API is stubbed (see semantic_steps.rb) so no scenario calls Voyage.

Given("the following papers are stored with embeddings and authors:") do |table|
  table.hashes.each do |row|
    paper = store_paper(title: row["title"])
    add_author(professors.fetch(row["professor"]), paper)
    embed_paper!(paper, concept_vector(row["concept"].to_i))
  end
end

Given("{string} also wrote {string} at concept {int}") do |professor, title, concept|
  paper = store_paper(title: title)
  add_author(professors.fetch(professor), paper)
  embed_paper!(paper, concept_vector(concept))
end
