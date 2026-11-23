# One Voyage embedding per paper, stored in paper_embeddings (db/paper_embeddings.sql).
class PaperEmbedding < ApplicationRecord
  self.primary_key = "paper_id"
  belongs_to :paper
  attribute :embedding, :string # pgvector text form "[x,y,...]"; Rails has no native vector type

  MAX_ABSTRACT = 6000 # characters; keeps every request well under Voyage's token limits

  # The exact text a paper is embedded from. Changing it means re-embedding every paper.
  def self.text_for(title, abstract)
    abstract.present? ? "#{title}\n\n#{abstract.first(MAX_ABSTRACT)}" : title.to_s
  end
end
