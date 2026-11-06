# The visitor's ranking selection: research areas, inclusive years and location.
class RankingFilters
  FIRST_YEAR = 2015 # the dataset starts here
  LOCATIONS = ["Worldwide"].freeze # all ten schools are in the US; country filter deferred

  attr_reader :areas, :from, :to, :location

  def self.year_options = (FIRST_YEAR..Date.current.year).to_a

  def initialize(params)
    picked = Array(params[:areas]) & VenueArea.areas
    @all_areas = params[:all_areas] == "1" || picked.empty?
    @areas = @all_areas ? VenueArea.areas : picked
    @from = year(params[:from], FIRST_YEAR)
    @to = year(params[:to], Date.current.year)
    @from, @to = @to, @from if @from > @to
    @location = LOCATIONS.first
  end

  def all_areas? = @all_areas

  def area_selected?(area) = !all_areas? && areas.include?(area)

  def years = from..to

  def to_params
    { all_areas: ("1" if all_areas?), areas: (areas unless all_areas?), from:, to:, location: }.compact
  end

  private

  def year(value, default)
    Integer(value.to_s, exception: false)&.clamp(FIRST_YEAR, Date.current.year) || default
  end
end
