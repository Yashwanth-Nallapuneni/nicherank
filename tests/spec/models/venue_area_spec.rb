require "rails_helper"

RSpec.describe VenueArea do
  it "lists the configured research areas" do
    expect(described_class.areas).to include("Machine learning", "Databases")
  end

  it "returns lowercased venues for the given areas" do
    venues = described_class.venues(["Machine learning", "Databases"])
    expect(venues).to include("neurips", "sigmod")
    expect(venues).to all(satisfy { |v| v == v.downcase })
  end

  it "returns no venues for an unknown area" do
    expect(described_class.venues(["Astrology"])).to eq([])
  end
end
