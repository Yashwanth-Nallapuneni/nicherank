# Research areas and the venues that count for each (config/venue_areas.yml).
module VenueArea
  MAP = YAML.load_file(Rails.root.join("config/venue_areas.yml")).freeze

  def self.areas = MAP.keys

  def self.venues(areas) = MAP.values_at(*areas).flatten.compact.map(&:downcase)
end
