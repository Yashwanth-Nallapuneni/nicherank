class RankingsController < ApplicationController
  MAX_QUERY = 300 # characters; longer searches are cut so each new query stays a small Voyage call
  MODES = { "keyword" => "Keyword", "semantic" => "Meaning (semantic)", "hybrid" => "Both (hybrid)" }.freeze

  def index
    @filters = RankingFilters.new(params)
    @ranking = Ranking.new(@filters)
    @expanded = params[:expand].to_i
    @saved_view = params[:view] == "saved"
    @query = params[:commit] == "Clear search" ? "" : params[:q].to_s.strip.first(MAX_QUERY)
    @sort = Paper::SORTS.key?(params[:sort]) ? params[:sort] : "relevance"
    @mode = MODES.key?(params[:mode]) ? params[:mode] : "keyword"
    @other_versions = {} # kept paper id => versions left out of meaning results (Paper.collapse_versions)
    return if @query.blank?

    @mode == "keyword" ? keyword_search : meaning_search
  end

  private

  def keyword_search
    # Counting stops at COUNT_CAP + 1 rows, so broad queries stay fast and show "1000+".
    found = Paper.matching(@query).limit(Paper::COUNT_CAP + 1).count
    @total_capped = found > Paper::COUNT_CAP
    @total = [found, Paper::COUNT_CAP].min
    paginate { |page| Paper.search(@query, page: page, sort: @sort) }
  end

  # Semantic and hybrid modes need the Voyage API and the embeddings table; fall back to keywords without them.
  def meaning_search
    ids = @mode == "semantic" ? Paper.semantic_ids(@query) : Paper.hybrid_ids(@query)
    versions = Paper.collapse_versions(ids)
    @other_versions = versions.hidden
    @total = versions.ids.size
    paginate { |page| Paper.ranked_page(versions.ids, page: page, sort: @sort) }
  rescue VoyageClient::Error, ActiveRecord::StatementInvalid => e
    Rails.logger.warn("Semantic search failed, using keywords: #{e.class}: #{e.message}")
    @notice = "Search by meaning is unavailable right now, so these are keyword results."
    @mode = "keyword"
    @other_versions = {}
    keyword_search
  end

  def paginate
    @pages = [(@total.to_f / Paper::SEARCH_LIMIT).ceil, 1].max
    @page = params[:page].to_i.clamp(1, @pages)
    @papers = yield(@page).load
  end
end
