# Ratings are source-specific: a journal's Q1 label is not a CORE letter grade.
class VenueRating < ApplicationRecord
  self.table_name = "venue_rankings"

  SOURCES = { "icore2026" => "ICORE 2026", "era2010" => "ERA 2010", "scimago2025" => "SCImago 2025" }.freeze
  GRADES = { "icore2026" => %w[A* A B C], "era2010" => %w[A* A B C], "scimago2025" => %w[Q1] }.freeze
  OPTIONS = { "" => "All venues", "rated" => "Has a listed rating", "unrated" => "No listed rating" }.merge(
    GRADES.flat_map { |source, grades| grades.map { |grade| ["#{source}:#{grade}", "#{SOURCES.fetch(source)} · #{grade}"] } }.to_h
  ).freeze

  scope :listed, -> { GRADES.map { |source, grades| where(source: source, ranking: grades) }.reduce(:or) }

  def self.normalize(value) = value.to_s.presence_in(OPTIONS.keys).presence

  def self.for_paper_type(type)
    case type
    when "conference-paper" then "conference"
    when "article" then "journal"
    end
  end

  def label = "#{SOURCES.fetch(source)} · #{ranking}"
end
