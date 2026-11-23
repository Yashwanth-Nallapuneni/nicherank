# University ranking for a RankingFilters selection.
# Score: each qualifying paper is worth 1, split equally among its roster-faculty
# authors (CSRankings-style adjusted count; external coauthors are not in the data).
class Ranking
  QUALIFYING_TYPES = %w[conference-paper article].freeze

  SORTS = {
    "highest_score" => "Highest score",
    "lowest_score" => "Lowest score",
    "name" => "Institution A–Z"
  }.freeze

  def self.normalize_sort(value) = SORTS.key?(value) ? value : "highest_score"

  Row = Struct.new(:rank, :university, :score)

  def initialize(filters)
    @filters = filters
  end

  # The search topic this ranking follows; nil for the plain venue ranking (see TopicRanking).
  def topic = nil

  # Papers that count: qualifying types, in the selected years, at a venue of the selected areas.
  def eligible_papers
    Paper.where(paper_type: QUALIFYING_TYPES, year: @filters.years)
         .where("lower(papers.venue) IN (?)", VenueArea.venues(@filters.areas).presence || [""])
  end

  def papers = eligible_papers

  def rows
    case @filters.institution_sort
    when "lowest_score"
      ranked_rows.sort_by { |row| [row.score, row.university.name.downcase, row.university.id] }
    when "name"
      ranked_rows.sort_by { |row| [row.university.name.downcase, row.university.id] }
    else
      ranked_rows
    end
  end

  def faculty(university)
    university.professors.where(id: Authorship.where(paper_id: papers.select(:id)).select(:professor_id)).order(:name)
  end

  def papers_for(professor)
    papers.joins(:authorships).where(authorships: { professor_id: professor.id }).order(year: :desc, title: :asc)
  end

  private

  # Assign ranks before applying display order, so sorting never renumbers them.
  def ranked_rows
    @ranked_rows ||= begin
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
