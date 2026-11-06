require "rails_helper"

RSpec.describe Ranking do
  let!(:north) { University.create!(openalex_id: "I920001", name: "Northbridge University") }
  let!(:lake) { University.create!(openalex_id: "I920002", name: "Lakeside University") }
  let!(:alice) { professor("A920001", "Alice", north) }
  let!(:dana) { professor("A920002", "Dana", north) }
  let!(:ben) { professor("A920003", "Ben", lake) }

  def professor(id, name, university)
    Professor.create!(openalex_id: id, name: name, title: "Professor",
                      university_id: university.id, match_confidence: "manual")
  end

  def paper(authors, year: 2022, venue: "NeurIPS", type: "conference-paper", title: "Paper #{@n = (@n || 0) + 1}")
    p = Paper.create!(openalex_id: "W92#{format('%04d', (@seq = (@seq || 0) + 1))}", title: title,
                      year: year, venue: venue, paper_type: type)
    Array(authors).each { |a| Authorship.create!(professor_id: a.id, paper_id: p.id) }
    p
  end

  def ranking(**params) = described_class.new(RankingFilters.new(params))
  def scores(r = ranking) = r.rows.to_h { |row| [row.university.name, row.score] }

  it "splits a paper's credit between roster co-authors at different schools" do
    paper([alice, ben])
    expect(scores).to eq("Northbridge University" => 0.5, "Lakeside University" => 0.5)
  end

  it "gives a school full credit when both co-authors are its own" do
    paper([alice, dana])
    expect(scores).to eq("Northbridge University" => 1.0)
  end

  it "counts only conference papers and articles" do
    paper(alice, type: "article")
    paper(alice, type: "preprint")
    paper(ben, type: "book-chapter")
    expect(scores).to eq("Northbridge University" => 1.0)
  end

  it "treats the year range as inclusive" do
    [2018, 2019, 2021, 2022].each { |y| paper(alice, year: y) }
    expect(scores(ranking(from: "2019", to: "2021"))).to eq("Northbridge University" => 2.0)
  end

  it "filters by area through a case-insensitive venue match" do
    paper(alice, venue: "neurips")
    paper(ben, venue: "SIGMOD")
    paper(ben, venue: "Some Workshop")
    expect(scores(ranking(areas: ["Machine learning"]))).to eq("Northbridge University" => 1.0)
    expect(scores(ranking(areas: ["Databases"]))).to eq("Lakeside University" => 1.0)
  end

  it "gives tied schools the same rank, ordered by name" do
    paper(alice)
    paper(ben)
    rows = ranking.rows
    expect(rows.map { |r| [r.rank, r.university.name] })
      .to eq([[1, "Lakeside University"], [1, "Northbridge University"]])
  end

  it "ranks the higher score first with the next rank number" do
    paper(alice)
    paper(dana)
    paper(ben)
    expect(ranking.rows.map { |r| [r.rank, r.university.name, r.score] })
      .to eq([[1, "Northbridge University", 2.0], [2, "Lakeside University", 1.0]])
  end

  it "lists only faculty who contributed under the filters" do
    paper(alice, venue: "NeurIPS")
    paper(dana, venue: "SIGMOD")
    expect(ranking.faculty(north)).to eq([alice, dana])
    expect(ranking(areas: ["Machine learning"]).faculty(north)).to eq([alice])
  end

  it "returns a professor's papers under the filters, newest first" do
    old = paper(alice, year: 2016, title: "Old")
    recent = paper(alice, year: 2023, title: "Recent")
    paper(alice, year: 2023, venue: "SIGMOD", title: "Database")
    paper(alice, year: 2023, type: "preprint", title: "Draft")
    expect(ranking(areas: ["Machine learning"]).papers_for(alice)).to eq([recent, old])
    expect(ranking(areas: ["Machine learning"], from: "2020").papers_for(alice)).to eq([recent])
  end
end
