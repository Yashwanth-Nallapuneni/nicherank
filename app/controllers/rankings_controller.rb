class RankingsController < ApplicationController
  def index
    @filters = RankingFilters.new(params)
    @ranking = Ranking.new(@filters)
    @expanded = params[:expand].to_i
    @query = params[:commit] == "Clear search" ? "" : params[:q].to_s.strip
    @sort = Paper::SORTS.key?(params[:sort]) ? params[:sort] : "relevance"
    return if @query.blank?

    @page = [params[:page].to_i, 1].max
    @papers = Paper.search(@query, page: @page, sort: @sort).load
    @total = @page == 1 && @papers.size < Paper::SEARCH_LIMIT ? @papers.size : Paper.matching(@query).count
    @pages = [(@total.to_f / Paper::SEARCH_LIMIT).ceil, 1].max
  end
end
