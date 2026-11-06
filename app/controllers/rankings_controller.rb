class RankingsController < ApplicationController
  def index
    @filters = RankingFilters.new(params)
    @ranking = Ranking.new(@filters)
    @expanded = params[:expand].to_i
    @query = params[:commit] == "Clear search" ? "" : params[:q].to_s.strip
    return if @query.blank?

    @papers = Paper.search(@query).load
    @total = @papers.size < Paper::SEARCH_LIMIT ? @papers.size : Paper.matching(@query).count
  end
end
