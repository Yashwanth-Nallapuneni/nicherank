class RankingsController < ApplicationController
  def index
    @filters = RankingFilters.new(params)
    @ranking = Ranking.new(@filters)
    @expanded = params[:expand].to_i
    @query = params[:commit] == "Clear search" ? "" : params[:q].to_s.strip
    @sort = Paper::SORTS.key?(params[:sort]) ? params[:sort] : "relevance"
    return if @query.blank?

    # Counting stops at COUNT_CAP + 1 rows, so broad queries stay fast and show "1000+".
    found = Paper.matching(@query).limit(Paper::COUNT_CAP + 1).count
    @total_capped = found > Paper::COUNT_CAP
    @total = [found, Paper::COUNT_CAP].min
    @pages = [(@total.to_f / Paper::SEARCH_LIMIT).ceil, 1].max
    @page = params[:page].to_i.clamp(1, @pages)
    @papers = Paper.search(@query, page: @page, sort: @sort).load
  end
end
