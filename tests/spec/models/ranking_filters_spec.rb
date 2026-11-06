require "rails_helper"

RSpec.describe RankingFilters do
  let(:year) { Date.current.year }

  def filters(**params) = described_class.new(params)

  it "defaults to all areas, 2015 to this year and Worldwide" do
    f = filters
    expect(f).to be_all_areas
    expect(f.areas).to eq(VenueArea.areas)
    expect(f.years).to eq(2015..year)
    expect(f.location).to eq("Worldwide")
  end

  it "keeps picked areas and marks them selected" do
    f = filters(areas: ["Databases"])
    expect(f).not_to be_all_areas
    expect(f.areas).to eq(["Databases"])
    expect(f.area_selected?("Databases")).to be true
    expect(f.area_selected?("Machine learning")).to be false
  end

  it "ignores unknown areas" do
    expect(filters(areas: ["Databases", "Astrology"]).areas).to eq(["Databases"])
    expect(filters(areas: ["Astrology"])).to be_all_areas
  end

  it "treats ticking All areas over picked areas as all areas" do
    f = filters(areas: ["Databases"], all_areas: "1")
    expect(f).to be_all_areas
    expect(f.areas).to eq(VenueArea.areas)
    expect(f.area_selected?("Databases")).to be false
  end

  it "treats ticking an area while All areas was showing as only that area" do
    f = filters(areas: ["Databases"], all_areas: "1", was_all: "1")
    expect(f).not_to be_all_areas
    expect(f.areas).to eq(["Databases"])
  end

  it "clamps years into the dataset range" do
    expect(filters(from: "1990", to: "3000").years).to eq(2015..year)
  end

  it "swaps years when from is after to" do
    expect(filters(from: "2024", to: "2019").years).to eq(2019..2024)
  end

  it "falls back to defaults for non-numeric years" do
    expect(filters(from: "abc", to: "").years).to eq(2015..year)
  end

  it "round-trips through to_params" do
    f = filters(areas: ["Databases", "Machine learning"], from: "2018", to: "2022")
    again = described_class.new(f.to_params)
    expect([again.areas, again.years, again.location]).to eq([f.areas, f.years, f.location])
    expect(filters.to_params).to include(all_areas: "1")
    expect(filters.to_params).not_to have_key(:areas)
  end
end
