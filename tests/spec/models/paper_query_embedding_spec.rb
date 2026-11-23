require "rails_helper"

RSpec.describe Paper, ".query_embedding" do
  let(:vector) { Array.new(VoyageClient::DIMENSIONS, 0.5) }

  describe ".normalize_query" do
    it "lowercases and collapses all whitespace, including tabs, newlines and non-breaking spaces" do
      expect(Paper.normalize_query("  Graph   Neural\tNetworks \n")).to eq("graph neural networks")
    end

    it "unifies Unicode compatibility forms" do
      expect(Paper.normalize_query("ＧＮＮ ﬁne-tuning")).to eq("gnn fine-tuning")
    end

    it "keeps punctuation and accents, which can change the meaning" do
      expect(Paper.normalize_query("C++ vs. C# — Café")).to eq("c++ vs. c# — café")
    end
  end

  it "embeds the normalized search text as a query" do
    expect(VoyageClient).to receive(:embed).with(["graph neural networks"], input_type: "query", timeout: 3).and_return([vector])

    expect(Paper.query_embedding("  Graph  Neural Networks ")).to eq(vector)
  end

  context "with a cache" do
    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it "makes one Voyage call for searches that differ only in case or spacing" do
      expect(VoyageClient).to receive(:embed).once.and_return([vector])

      ["Graph Neural Networks", "graph neural networks", " graph   neural NETWORKS "].each do |query|
        expect(Paper.query_embedding(query)).to eq(vector)
      end
    end

    it "still embeds searches with different words separately" do
      expect(VoyageClient).to receive(:embed).twice.and_return([vector])

      Paper.query_embedding("graph neural networks")
      Paper.query_embedding("graph neural network")
    end
  end
end
