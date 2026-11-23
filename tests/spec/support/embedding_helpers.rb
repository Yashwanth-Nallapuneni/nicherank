# frozen_string_literal: true

# Hand-made embeddings for semantic search tests. No test ever calls the real Voyage API:
# query vectors are stubbed with stub_query_embedding.
module EmbeddingHelpers
  # A 512-dimension vector pointing mostly along `axis`, with an optional pull towards `toward`.
  def concept_vector(axis, toward: nil, weight: 0.0)
    vector = Array.new(VoyageClient::DIMENSIONS, 0.0)
    vector[axis] = 1.0
    vector[toward] = weight if toward
    vector
  end

  def embed_paper!(paper, vector)
    PaperEmbedding.create!(paper: paper, embedding: "[#{vector.join(',')}]", model: "test")
  end

  def stub_query_embedding(vectors_by_query)
    allow(Paper).to receive(:query_embedding) do |query|
      vectors_by_query.fetch(query) { raise VoyageClient::Error, "no stub for #{query.inspect}" }
    end
  end
end
