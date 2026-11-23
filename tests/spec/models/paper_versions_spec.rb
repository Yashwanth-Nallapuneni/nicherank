require "rails_helper"

RSpec.describe Paper, ".collapse_versions" do
  let(:university) { University.create!(openalex_id: "I980001", name: "Northbridge University") }
  let(:alice) { professor("Alice Researcher") }
  let(:bob) { professor("Bob Builder") }

  def professor(name)
    @prof_seq = (@prof_seq || 0) + 1
    Professor.create!(openalex_id: "A98#{format('%04d', @prof_seq)}", name: name, title: "Professor",
                      university_id: university.id, match_confidence: "manual")
  end

  def paper(title, type: "conference-paper", year: 2022, authors: [alice])
    @paper_seq = (@paper_seq || 0) + 1
    Paper.create!(openalex_id: "W98#{format('%04d', @paper_seq)}", title: title, year: year, paper_type: type).tap do |p|
      authors.each { |author| Authorship.create!(professor_id: author.id, paper_id: p.id) }
    end
  end

  def collapse(*papers) = Paper.collapse_versions(papers.map(&:id))

  it "keeps the published version of a preprint, at the preprint's better rank" do
    other = paper("Learning to rank robot grasps")
    preprint = paper("Join ordering with mixed integer programming", type: "preprint", year: 2021)
    published = paper("Join ordering with mixed integer programming", type: "conference-paper", year: 2022)

    result = collapse(preprint, other, published)
    expect(result.ids).to eq([published.id, other.id])
    expect(result.hidden).to eq(published.id => [["preprint", 2021]])
  end

  it "keeps the higher-ranked copy when both versions are published" do
    journal = paper("Verified compilation of differential privacy", type: "article")
    conference = paper("Verified compilation of differential privacy", type: "conference-paper")

    expect(collapse(journal, conference).ids).to eq([journal.id])
    expect(collapse(conference, journal).ids).to eq([conference.id])
  end

  it "prefers a book chapter over a preprint" do
    preprint = paper("A survey of program synthesis methods", type: "preprint")
    chapter = paper("A survey of program synthesis methods", type: "book-chapter")

    expect(collapse(preprint, chapter).ids).to eq([chapter.id])
  end

  it "matches titles regardless of case, accents and punctuation" do
    a = paper("Multi-objective parametric query optimization")
    b = paper("Multi-Objective Parametric Query Optimization.", type: "article", year: 2021)
    c = paper("Multi objective paramétric query optimization", type: "preprint", year: 2020)

    result = collapse(a, b, c)
    expect(result.ids).to eq([a.id])
    expect(result.hidden).to eq(a.id => [["article", 2021], ["preprint", 2020]])
  end

  it "does not merge short, generic titles" do
    expect(collapse(paper("Graph Neural Networks", type: "book-chapter"), paper("Graph Neural Networks", type: "book-chapter")).ids.size).to eq(2)
  end

  it "does not merge papers that share no roster author" do
    expect(collapse(paper("Learning to rank robot grasps"), paper("Learning to rank robot grasps", authors: [bob])).ids.size).to eq(2)
  end

  it "does not merge papers published more than three years apart" do
    early = paper("Introduction to the special issue on databases", year: 2016)
    late = paper("Introduction to the special issue on databases", year: 2020)
    expect(collapse(early, late).ids).to eq([early.id, late.id])
  end

  it "merges a copy that shares an author with either of the other copies" do
    a = paper("Robust planning under uncertainty for robots", authors: [alice])
    b = paper("Robust planning under uncertainty for robots", type: "preprint", authors: [alice, bob])
    c = paper("Robust planning under uncertainty for robots", type: "preprint", authors: [bob])

    expect(collapse(c, b, a).ids).to eq([a.id])
  end

  it "leaves short lists alone and drops ids that are not papers" do
    only = paper("Learning to rank robot grasps")
    expect(Paper.collapse_versions([]).ids).to eq([])
    expect(Paper.collapse_versions([only.id]).ids).to eq([only.id])
    expect(Paper.collapse_versions([only.id, -1]).ids).to eq([only.id])
  end
end
