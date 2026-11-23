require "rails_helper"
require_relative "../support/embedding_helpers"

RSpec.describe TopicRanking do
  include EmbeddingHelpers

  let(:query) { "teaching robots by showing them" }
  let(:north) { University.create!(openalex_id: "I960001", name: "Northbridge University") }
  let(:south) { University.create!(openalex_id: "I960002", name: "Southfield University") }
  let(:west) { University.create!(openalex_id: "I960003", name: "Westbrook University") }

  def professor(name, university)
    @prof_seq = (@prof_seq || 0) + 1
    Professor.create!(openalex_id: "A96#{format('%04d', @prof_seq)}", name: name, title: "Professor",
                      university_id: university.id, match_confidence: "manual")
  end

  # vector: nil leaves the paper without an embedding.
  def paper(title, authors, vector:, year: 2024, venue: "NeurIPS")
    @paper_seq = (@paper_seq || 0) + 1
    record = Paper.create!(openalex_id: "W96#{format('%04d', @paper_seq)}", title: title, year: year, venue: venue,
                           paper_type: "conference-paper", citations: 0)
    authors.each { |author| Authorship.create!(professor_id: author.id, paper_id: record.id) }
    embed_paper!(record, vector) if vector
    record
  end

  # Cosine similarity to concept 0: exact = 1.0, close ≈ 0.958 (inside the 0.08 band), far ≈ 0.894 (outside).
  # These fixtures have fewer than ANCHOR papers, so the band is measured from the best match.
  def exact = concept_vector(0)
  def close = concept_vector(0, toward: 1, weight: 0.3)
  def far = concept_vector(0, toward: 1, weight: 0.5)
  def off_topic = concept_vector(2)

  def filters(**params) = RankingFilters.new({ from: 2020, to: 2026 }.merge(params))
  def ranking(**params) = TopicRanking.new(filters(**params), query)
  def scores(ranking) = ranking.rows.to_h { |row| [row.university.name, row.score] }

  let(:alice) { professor("Alice North", north) }
  let(:bob) { professor("Bob South", south) }

  before { stub_query_embedding(query => exact) }

  it "ranks by relevance to the topic, not by paper count" do
    paper("Imitation from video", [alice], vector: exact)
    paper("Policy learning from demonstrations", [bob], vector: close)
    3.times { |i| paper("Column store tuning #{i}", [bob], vector: off_topic) }

    expect(ranking.rows.map { |row| [row.rank, row.university.name] })
      .to eq([[1, "Northbridge University"], [2, "Southfield University"]])
    expect(scores(ranking)).to eq("Northbridge University" => 1.0, "Southfield University" => 0.47)
  end

  it "leaves out papers outside the relevance band and universities with no topic papers" do
    paper("Imitation from video", [alice], vector: exact)
    paper("Loosely related robotics", [bob], vector: far)
    paper("Column store tuning", [professor("Wendy West", west)], vector: off_topic)

    expect(scores(ranking)).to eq("Northbridge University" => 1.0)
  end

  it "splits a paper among its authors and never counts it twice for one university" do
    carol = professor("Carol North", north)
    paper("Imitation from video", [alice, carol, bob], vector: exact)

    expect(scores(ranking)).to eq("Northbridge University" => 0.67, "Southfield University" => 0.33)
  end

  it "respects the year and area filters" do
    paper("Imitation from video", [alice], vector: close)
    paper("Old imitation paper", [bob], vector: exact, year: 2016)
    paper("Imitation for databases", [bob], vector: exact, venue: "SIGMOD")

    expect(scores(ranking(areas: ["Machine learning"])).keys).to eq(["Northbridge University"])
    # With every area, the SIGMOD paper counts and becomes the best match; 2016 stays out of 2020–2026.
    expect(scores(ranking)).to eq("Southfield University" => 1.0, "Northbridge University" => 0.47)
  end

  it "ignores papers that have no embedding yet" do
    paper("Imitation from video", [alice], vector: nil)
    paper("Policy learning from demonstrations", [bob], vector: close)

    expect(scores(ranking)).to eq("Southfield University" => 1.0)
  end

  it "lists faculty and their papers by topic score" do
    dave = professor("Dave North", north)
    best = paper("Imitation from video", [dave], vector: exact)
    second = paper("Policy learning from demonstrations", [alice], vector: close)
    paper("Column store tuning", [alice], vector: off_topic)
    also_alice = paper("Imitation, again", [alice], vector: exact)

    topic = ranking
    expect(topic.faculty(north).map(&:name)).to eq(["Alice North", "Dave North"])
    expect(topic.professor_score(alice)).to eq(1.47)
    expect(topic.papers_for(alice).to_a).to eq([also_alice, second])
    expect(topic.papers_for(dave).to_a).to eq([best])
  end

  it "follows the institution sort without renumbering ranks" do
    paper("Imitation from video", [alice], vector: exact)
    paper("Policy learning from demonstrations", [bob], vector: close)

    expect(ranking(institution_sort: "lowest_score").rows.map { |row| [row.rank, row.university.name] })
      .to eq([[2, "Southfield University"], [1, "Northbridge University"]])
  end

  it "measures the band from the ANCHOR-th match, so one near-duplicate of the query does not shrink it" do
    stub_const("TopicRanking::ANCHOR", 2)
    paper("The query, almost word for word", [alice], vector: exact)
    paper("Policy learning from demonstrations", [bob], vector: close)
    paper("Loosely related robotics", [professor("Wendy West", west)], vector: far)

    # Band runs from close (0.958) down to 0.878, so far (0.894) now counts, at a low weight.
    expect(scores(ranking)).to eq("Northbridge University" => 1.0, "Southfield University" => 1.0, "Westbrook University" => 0.21)
  end

  it "ranks nothing when no paper is embedded" do
    paper("Imitation from video", [alice], vector: nil)
    expect(ranking.rows).to be_empty
  end
end
