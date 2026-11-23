class ProfessorsController < ApplicationController
  def show
    @professor = Professor.includes(:university).find(params[:id])
    @filters = RankingFilters.new(params)
    @papers = Ranking.new(@filters).papers_for(@professor)
    @back = @filters.to_params.merge(expand: @professor.university_id, view: ("saved" if params[:view] == "saved"), q: params[:q].presence, mode: params[:mode].presence_in(%w[semantic hybrid])).compact
  end
end
