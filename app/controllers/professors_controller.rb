class ProfessorsController < ApplicationController
  def show
    @professor = Professor.includes(:university).find(params[:id])
    @filters = RankingFilters.new(params)
    @papers = Ranking.new(@filters).papers_for(@professor)
    @back = @filters.to_params.merge(expand: @professor.university_id, q: params[:q].presence).compact
  end
end
