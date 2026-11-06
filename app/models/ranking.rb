# University ranking for a RankingFilters selection.
# Score: each qualifying paper is worth 1, split equally among its roster-faculty
# authors (CSRankings-style adjusted count; external coauthors are not in the data).
class Ranking
  QUALIFYING_TYPES = %w[conference-paper article].freeze

  Row = Struct.new(:rank, :university, :score)

  def initialize(filters)
    @filters = filters
  end

  def papers
    Paper.where(paper_type: QUALIFYING_TYPES, year: @filters.years)
         .where("lower(papers.venue) IN (?)", VenueArea.venues(@filters.areas).presence || [""])
  end

  def rows
    @rows ||= begin
      unis = University.where(id: scores.keys).index_by(&:id)
      sorted = scores.sort_by { |id, score| [-score, unis[id].name] }
      rank = previous = nil
      sorted.each_with_index.map do |(id, score), i|
        rank = i + 1 unless score == previous
        previous = score
        Row.new(rank, unis[id], score)
      end
    end
  end

  def faculty(university)
    university.professors.where(id: Authorship.where(paper_id: papers.select(:id)).select(:professor_id)).order(:name)
  end

  def papers_for(professor)
    papers.joins(:authorships).where(authorships: { professor_id: professor.id }).order(year: :desc, title: :asc)
  end

  private

  def scores
    @scores ||= begin
      credit = Authorship.where(paper_id: papers.select(:id))
                         .group(:paper_id).select("paper_id, 1.0 / count(*) AS credit")
      Authorship.joins(:professor)
                .joins("JOIN (#{credit.to_sql}) credit ON credit.paper_id = authorships.paper_id")
                .group("professors.university_id")
                .sum("credit.credit")
                .transform_values { |score| score.to_f.round(2) }
    end
  end
end
