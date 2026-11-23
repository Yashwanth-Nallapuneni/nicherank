require "rails_helper"
require_relative "../support/embedding_helpers"

RSpec.describe Paper, "semantic and hybrid search" do
  include EmbeddingHelpers

  def paper(title, year: 2022, **attrs)
    Paper.create!(openalex_id: "W95#{format('%04d', (@seq = (@seq || 0) + 1))}", title: title,
                  year: year, paper_type: "article", **attrs)
  end

  let!(:robots) { paper("Imitation from video demonstrations", year: 2021).tap { |p| embed_paper!(p, concept_vector(0)) } }
  let!(:near_robots) { paper("Policy learning for manipulators", year: 2024).tap { |p| embed_paper!(p, concept_vector(1, toward: 0, weight: 0.6)) } }
  let!(:databases) { paper("Robot-free query optimization", year: 2023).tap { |p| embed_paper!(p, concept_vector(2)) } }

  before { stub_query_embedding("teaching robots by showing them" => concept_vector(0, toward: 1, weight: 0.2)) }

  it "orders papers by closeness in meaning, even with no shared words" do
    expect(Paper.semantic_ids("teaching robots by showing them")).to eq([robots.id, near_robots.id, databases.id])
  end

  it "skips papers that have no embedding yet" do
    unembedded = paper("Teaching robots by showing them")
    expect(Paper.semantic_ids("teaching robots by showing them")).not_to include(unembedded.id)
  end

  it "keeps the given ranking in ranked_page and loads one page" do
    stub_const("Paper::SEARCH_LIMIT", 2)
    ids = [databases.id, robots.id, near_robots.id]
    expect(Paper.ranked_page(ids).to_a).to eq([databases, robots])
    expect(Paper.ranked_page(ids, page: 2).to_a).to eq([near_robots])
  end

  it "applies a chosen sort to the ranked papers" do
    ids = Paper.semantic_ids("teaching robots by showing them")
    expect(Paper.ranked_page(ids, sort: "year_desc").map(&:year)).to eq([2024, 2023, 2021])
  end

  it "returns nothing for an empty ranking" do
    expect(Paper.ranked_page([])).to be_empty
  end

  it "hybrid puts papers found by both keyword and meaning first" do
    stub_query_embedding("robot" => concept_vector(0))
    # "robot" matches only the databases paper by keyword; meaning ranks robots first.
    ids = Paper.hybrid_ids("robot")
    expect(ids.first(2)).to contain_exactly(robots.id, databases.id)
    expect(ids).to include(near_robots.id)
  end

  it "builds the embedding text from title and abstract" do
    expect(PaperEmbedding.text_for("T", "A")).to eq("T\n\nA")
    expect(PaperEmbedding.text_for("T", nil)).to eq("T")
    expect(PaperEmbedding.text_for("T", "x" * 9000).length).to eq(3 + PaperEmbedding::MAX_ABSTRACT)
  end
end
