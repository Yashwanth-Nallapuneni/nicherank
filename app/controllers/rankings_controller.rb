class RankingsController < ApplicationController
  def index
    @filters = RankingFilters.new(params)
    @ranking = Ranking.new(@filters)
    @expanded = params[:expand].to_i
    @query = params[:commit] == "Clear search" ? "" : params[:q].to_s.strip
    @papers = Paper.search(@query) if @query.present?
  end
end
