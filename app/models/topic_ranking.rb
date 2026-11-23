# Semantic ("niche") ranking: universities ranked for a search topic instead of for whole areas.
#
# It counts the same papers as Ranking (qualifying types, selected years, venues of the selected
# areas), but only the ones closest in meaning to the search, and each by how close it is:
#
# 1. Take the POOL qualifying papers whose embeddings are nearest the query (cosine similarity).
# 2. Keep those within BAND below the ANCHOR-th best match. Similarities differ between queries,
#    so the cutoff is relative, and anchoring on the 10th match (not the 1st) stops one
#    near-duplicate of the query from shrinking the band. Fewer than ANCHOR candidates: the best.
# 3. Each kept paper is worth a relevance weight: 1 at or above the anchor, falling to 0 at the
#    edge of the band. It is split equally among its roster-faculty authors, exactly as Ranking
#    splits 1 point. A university's score is the sum of its professors' shares, so a paper shared
#    inside one university is never counted twice.
#
# Calibrated on the 52-school data: BAND 0.08 keeps about 100-450 papers per topic.
class TopicRanking < Ranking
  POOL = 500   # nearest qualifying papers considered
  ANCHOR = 10  # the band is measured from this match
  BAND = 0.08  # cosine-similarity band below the anchor that still counts

  # vector: the query's embedding (Paper.query_vector) when the caller already has it.
  def initialize(filters, query, vector: nil)
    super(filters)
    @query = query
    @vector = vector
  end

  def topic = @query

  def papers = eligible_papers.where(id: relevance.keys)

  # Professors with at least one topic paper, strongest first.
  def faculty(university)
    university.professors.where(id: professor_scores.keys).sort_by { |p| [-professor_scores[p.id], p.name] }
  end

  # A professor's topic papers, most relevant first.
  def papers_for(professor)
    ordered = relevance.sort_by { |id, weight| [-weight, id] }.map(&:first)
    return Paper.none if ordered.empty?

    papers.joins(:authorships).where(authorships: { professor_id: professor.id })
          .order(Arel.sql(Paper.sanitize_sql_array(["array_position(ARRAY[?]::bigint[], papers.id)", ordered])))
  end

  def professor_score(professor) = professor_scores.fetch(professor.id, 0.0).round(2)

  # paper id => relevance weight in (0, 1].
  def relevance
    @relevance ||= begin
      similarity = nearest_papers
      ordered = similarity.values.sort.reverse
      floor = (ordered[ANCHOR - 1] || ordered.first || 0) - BAND
      similarity.select { |_, s| s > floor }.transform_values { |s| ((s - floor) / BAND).clamp(0.0, 1.0) }
    end
  end

  private

  # paper id => cosine similarity, for the POOL nearest qualifying papers.
  def nearest_papers
    @vector ||= Paper.query_vector(@query)
    distance = Paper.sanitize_sql_array(["paper_embeddings.embedding <=> ?::vector", @vector])
    # "+ 0" makes Postgres compare every qualifying paper exactly. The HNSW index would search all
    # 200k+ papers first and drop the ones outside the filters, returning too few. Ties break on id
    # so the same search always counts the same papers.
    eligible_papers.joins("JOIN paper_embeddings ON paper_embeddings.paper_id = papers.id")
                   .order(Arel.sql("(#{distance}) + 0, papers.id"))
                   .limit(POOL)
                   .pluck(:id, Arel.sql("1 - (#{distance})"))
                   .to_h { |id, similarity| [id, similarity.to_f] }
  end

  # [professor id, university id, share] for every author of every topic paper.
  def shares
    @shares ||= Authorship.joins(:professor).where(paper_id: relevance.keys)
                          .pluck(:paper_id, :professor_id, "professors.university_id")
                          .group_by(&:first)
                          .flat_map { |paper_id, rows| rows.map { |_, prof, uni| [prof, uni, relevance[paper_id] / rows.size] } }
  end

  def professor_scores
    @professor_scores ||= shares.each_with_object(Hash.new(0.0)) { |(prof, _, share), totals| totals[prof] += share }
  end

  def scores
    @scores ||= shares.each_with_object(Hash.new(0.0)) { |(_, uni, share), totals| totals[uni] += share }
                      .transform_values { |score| score.round(2) }
                      .reject { |_, score| score.zero? }
  end
end
