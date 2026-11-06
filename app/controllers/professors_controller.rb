class ProfessorsController < ApplicationController
  def show
    @professor = Professor.includes(:university).find(params[:id])
    @filters = RankingFilters.new(params)
    @papers = Ranking.new(@filters).papers_for(@professor)
  end
end
