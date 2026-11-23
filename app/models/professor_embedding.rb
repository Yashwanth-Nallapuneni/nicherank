# Read the research profiles already maintained by the data pipeline.
class ProfessorEmbedding < ApplicationRecord
  self.primary_key = "professor_id"
  belongs_to :professor
  attribute :embedding, :string

  PAGE_SIZE = 20

  def self.with_profiles(institution = nil)
    scope = joins(professor: :university).where("professor_embeddings.papers > 0")
    institution.present? ? scope.where(universities: { openalex_id: institution }) : scope
  end

  def self.nearest(query)
    values = Paper.query_embedding(query)
    unless values.is_a?(Array) && values.size == VoyageClient::DIMENSIONS &&
           values.all? { |v| v.is_a?(Numeric) && v.finite? } && values.any? { |v| v != 0 }
      raise VoyageClient::Error, "Invalid query embedding"
    end
    vector = "[#{values.map { |v| Float(v) }.join(',')}]"
    distance = sanitize_sql_array(["professor_embeddings.embedding <=> ?::vector", vector])
    # The small profile table uses exact distances; ties stay stable across pages.
    # Use vectors for ordering in Postgres without transferring them into each result card.
    select(:professor_id, :papers).order(Arel.sql("#{distance}, professors.name, professors.id"))
      .includes(professor: :university)
  end
end
