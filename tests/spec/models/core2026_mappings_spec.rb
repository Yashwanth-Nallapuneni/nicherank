require "rails_helper"
require_relative "../../../data/script/data/map_venue_rankings"
require_relative "../../../data/script/data/build_venue_rankings"

RSpec.describe "Reviewed CORE 2026 data" do
  it "reproduces every shipped conference mapping with current source grades, including NeurIPS and FOCS" do
    directory = Rails.root.join("data/db/data/manual")
    read = ->(name) { NicheRank.read_csv(directory.join("#{name}.csv")) }
    mapper = NicheRank::VenueRankingMapping
    current = read.call("icore2026")
    aliases = mapper.legacy_aliases(read.call("venue_tiers"), read.call("core2023"), current) + read.call("icore2026_aliases")
    mappings = read.call("venue_ranking_mappings")
    conferences = mappings.select { |row| row["source"] == "icore2026" }
    rebuilt, reviews = mapper.conferences(conferences, current, aliases: aliases)
    identity = ->(rows) { rows.to_h { |row| [row["venue"], row.values_at("core_id", "rank")] } }
    expect(reviews).to be_empty
    expect(identity.call(rebuilt)).to eq(identity.call(conferences))
    expect(identity.call(rebuilt)).to include(
      "neural information processing systems" => ["98", "A*"],
      "Annual Symposium on Foundations of Computer Science" => ["745", "A*"]
    )
    expect(identity.call(rebuilt)).not_to include(
      "CAA Symposium on Fault Detection, Supervision and Safety for Technical Processes (SAFEPROCESS)",
      "IEEE International Conference on Computational Science and Engineering (CSE) and IEEE International Conference on Embedded and Ubiquitous Computing (EUC)"
    )
    lists = NicheRank::VenueRankingBuild::LISTS.transform_values do |file, id|
      NicheRank.read_csv(directory.join(file)).to_h { |r| [r[id], r.merge("rank" => r["rank"] || r["ranking"])] }
    end
    expect(NicheRank::VenueRankingBuild.build(mappings, lists)).to eq(read.call("venue_rankings"))
  end
end
