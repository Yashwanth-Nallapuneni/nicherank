require "rails_helper"

RSpec.describe Paper, ".search" do
  let(:uni) { University.create!(openalex_id: "I930001", name: "Search University") }

  def paper(title, **attrs)
    Paper.create!(openalex_id: "W93#{format('%04d', (@seq = (@seq || 0) + 1))}", title: title,
                  year: 2022, paper_type: "article", **attrs)
  end

  def professor(n)
    Professor.create!(openalex_id: "A93000#{n}", name: "Prof #{n}", title: "Professor",
                      university_id: uni.id, match_confidence: "manual")
  end

  it "matches title, abstract, keywords and primary topic case-insensitively" do
    by_title = paper("Graph Neural Networks")
    by_abstract = paper("Untitled one", abstract: "We study graph partitioning.")
    by_keywords = paper("Untitled two", keywords: "GRAPH theory")
    by_topic = paper("Untitled three", primary_topic: "Graph algorithms")
    expect(Paper.search("GRAPH")).to contain_exactly(by_title, by_abstract, by_keywords, by_topic)
  end

  it "does not match unrelated papers" do
    paper("Quantum error correction")
    expect(Paper.search("compilers")).to be_empty
  end

  it "ranks a title match above an abstract-only match" do
    abstract_only = paper("Something else", abstract: "A note on compilers.")
    in_title = paper("Optimizing compilers")
    expect(Paper.search("compilers").to_a).to eq([in_title, abstract_only])
  end

  it "returns each paper once even with several authors" do
    p = paper("Distributed consensus")
    [1, 2, 3].each { |n| Authorship.create!(professor_id: professor(n).id, paper_id: p.id) }
    results = Paper.search("consensus").to_a
    expect(results).to eq([p])
    expect(results.first.professors.size).to eq(3)
  end

  it "caps results at SEARCH_LIMIT" do
    stub_const("Paper::SEARCH_LIMIT", 2)
    3.times { |i| paper("Robotics study #{i}") }
    expect(Paper.search("robotics").to_a.size).to eq(2)
  end
end
