class ResearchersController < ApplicationController
  def index
    @filters = RankingFilters.new({})
    @query = params[:q].to_s.strip.first(300)
    @mode, @sort = "keyword", "relevance"
    @universities = University.order(:name)
    @institution = params[:institution].presence_in(@universities.map(&:openalex_id))
    @page = 1
    @matches = []
    return if @query.blank?

    profiles = ProfessorEmbedding.with_profiles(@institution)
    @total = profiles.count
    @pages = [(@total.to_f / ProfessorEmbedding::PAGE_SIZE).ceil, 1].max
    @page = params[:page].to_i.clamp(1, @pages)
    return if @total.zero?

    @matches = profiles.nearest(@query).limit(ProfessorEmbedding::PAGE_SIZE)
                       .offset((@page - 1) * ProfessorEmbedding::PAGE_SIZE).to_a
  rescue VoyageClient::Error, ActiveRecord::StatementInvalid => e
    Rails.logger.warn("Faculty search unavailable: #{e.class}")
    @notice = "Faculty search is unavailable right now. Try again shortly or browse institution rankings."
  end
end
