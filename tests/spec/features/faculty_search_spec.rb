require "rails_helper"
require_relative "../support/embedding_helpers"

RSpec.describe "Find faculty by research topic", type: :feature do
  include EmbeddingHelpers

  let!(:north) { University.create!(openalex_id: "I99001", name: "Northbridge") }
  let!(:lake) { University.create!(openalex_id: "I99002", name: "Lakeside") }

  def researcher(name, school, vector: nil, papers: 4)
    professor = Professor.create!(openalex_id: "A99#{@id = (@id || 0) + 1}", name: name,
                                  title: "Professor", university: school, match_confidence: "manual")
    ProfessorEmbedding.create!(professor: professor, embedding: "[#{vector.join(',')}]", papers: papers) if vector
    professor
  end

  it "orders by meaning, breaks ties consistently and searches within the chosen school" do
    alice = researcher("Alice", north, vector: concept_vector(0))
    amy = researcher("Amy", lake, vector: concept_vector(0))
    ben = researcher("Ben", lake, vector: concept_vector(1))
    researcher("Missing", north)
    researcher("Empty", north, vector: concept_vector(0), papers: 0)
    stub_query_embedding("robot demonstrations" => concept_vector(0))
    results = ProfessorEmbedding.with_profiles.nearest("robot demonstrations").to_a
    expect(results.map(&:professor)).to eq([alice, amy, ben])
    expect(results.all? { |r| r.association(:professor).loaded? && r.professor.association(:university).loaded? }).to be(true)
    expect(ProfessorEmbedding.with_profiles(lake.openalex_id).nearest("robot demonstrations").map(&:professor)).to eq([amy, ben])
  end

  it "does not call the embedding service for a blank topic or an institution without profiles" do
    expect(Paper).not_to receive(:query_embedding)
    visit faculty_path(q: "   ")
    expect(page).to have_text("Enter a research topic")
    visit faculty_path(q: "robotics", institution: north.openalex_id)
    expect(page).to have_text("No searchable faculty profiles")
  end

  it "bounds long input and pages, ignores unknown institutions and escapes displayed topics" do
    researcher("Alice", north, vector: concept_vector(0))
    query = "<script>alert(1)</script>" + "x" * 400
    expect(Paper).to receive(:query_embedding).with(query.first(300)).and_return(concept_vector(0))
    visit faculty_path(q: query, institution: "I-do-not-exist", page: 99_999)
    expect(page).to have_select("Institution", selected: "All institutions")
    expect(page).to have_css('[data-testid="faculty-result"]', count: 1)
    expect(page).to have_text(query.first(300))
    expect(page).not_to have_css("h2 script", visible: :all)
  end

  it "rejects invalid query vectors before passing them to Postgres" do
    [[], Array.new(512, 0.0), Array.new(512, Float::NAN)].each do |vector|
      allow(Paper).to receive(:query_embedding).and_return(vector)
      expect { ProfessorEmbedding.with_profiles.nearest("robotics").load }.to raise_error(VoyageClient::Error, "Invalid query embedding")
    end
  end

  it "keeps the topic and institution visible when profile storage is unavailable" do
    allow(ProfessorEmbedding).to receive(:with_profiles).and_raise(ActiveRecord::StatementInvalid, "missing profile table")
    visit faculty_path(q: "robotics", institution: north.openalex_id)
    expect(page).to have_text("Faculty search is unavailable right now")
    expect(page).to have_field("Research topic", with: "robotics")
    expect(page).to have_select("Institution", selected: "Northbridge")
    expect(page).to have_link("Browse rankings", href: root_path)
    expect(page).to have_no_css('[data-testid="faculty-result"]')
  end
end
