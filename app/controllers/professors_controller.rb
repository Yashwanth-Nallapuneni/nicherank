class ProfessorsController < ApplicationController
  def show
    @professor = Professor.includes(:university).find(params[:id])
    @filters = RankingFilters.new(params)
    query = params[:q].to_s.strip.first(RankingsController::MAX_QUERY)
    mode = params[:mode].presence_in(%w[semantic hybrid])
    @ranking = (topic_ranking(query) if mode && query.present?) || Ranking.new(@filters)
    @papers = @ranking.papers_for(@professor).to_a
    @back = @filters.to_params.merge(
      expand: @professor.university_id,
      view: ("saved" if params[:view] == "saved"),
      q: query.presence,
      mode: mode
    ).compact
  end

  private

  # Opened from a topic ranking: list this professor's papers on that topic. Without the
  # embedding service, show the plain list instead, as the rankings page does.
  def topic_ranking(query)
    TopicRanking.new(@filters, query).tap(&:relevance)
  rescue VoyageClient::Error, ActiveRecord::StatementInvalid => e
    Rails.logger.warn("Topic papers unavailable, showing all papers: #{e.class}: #{e.message}")
    nil
  end
end
