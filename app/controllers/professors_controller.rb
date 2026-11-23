class ProfessorsController < ApplicationController
  def show
    if params[:faculty_q].present?
      @faculty_back = { q: params[:faculty_q].to_s.strip.first(300),
                        institution: params[:faculty_institution].to_s.presence,
                        page: params[:faculty_page].to_i.clamp(1, 10_000) }.compact
    end
    @professor = Professor.includes(:university).find(params[:id])
    @filters = RankingFilters.new(params)
    @saved_view = params[:view] == "saved"
    @papers = Ranking.new(@filters).papers_for(@professor)
    @back = @filters.to_params.merge(
      expand: @professor.university_id,
      view: ("saved" if params[:view] == "saved"),
      q: params[:q].presence,
      mode: params[:mode].presence_in(%w[semantic hybrid])
    ).compact
  end
end
