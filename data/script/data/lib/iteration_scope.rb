# frozen_string_literal: true

require_relative 'iteration2_rosters'
require_relative 'iteration3_rosters'

module NicheRank
  # Which batch of added schools an identity/collection script works on, chosen with
  # NICHE_SCOPE=iteration2|iteration3. Every batch keeps its own proposal, review and
  # evidence files, so one batch never rewrites another batch's audited decisions.
  # For iteration2 the names below are exactly the files that already exist.
  class IterationScope
    SCHOOLS = {
      'iteration2' => PublicPreparation::ITERATION2_SCHOOLS,
      'iteration3' => PublicPreparation::ITERATION3_SCHOOLS
    }.freeze
    # Raw OpenAlex responses newer than this date belong to the batch's collection.
    COLLECTION_SINCE = { 'iteration2' => '2026-11-15', 'iteration3' => '2026-11-19' }.freeze

    attr_reader :name

    def self.names = SCHOOLS.keys

    # nil name and no default means "no scope" (the original ten-school behaviour).
    def self.fetch(name = ENV['NICHE_SCOPE'], default: nil)
      name = default if name.to_s.strip.empty?
      return nil if name.nil?
      raise ArgumentError, "Unknown NICHE_SCOPE #{name.inspect}; use #{names.join(' or ')}" unless SCHOOLS.key?(name)
      new(name)
    end

    def initialize(name)
      @name = name
    end

    def schools = SCHOOLS.fetch(name)
    def label = name.sub('iteration', 'iteration ') # "iteration 3"
    def collection_since = COLLECTION_SINCE.fetch(name)

    # Files under db/data/manual
    def proposals_file = "#{name}_author_match_proposals.csv"
    def retry_file = "#{name}_retry_proposals.csv"
    def orcid_file = "#{name}_orcid_proposals.csv" # third pass: ORCID from CSRankings
    def review_file = "#{name}_review.csv"
    def corrections_file = "#{name}_identity_corrections.csv"
    def alias_evidence_file = "#{name}_alias_evidence.json"

    # Paths relative to the data root
    def tmp_dir = File.join('tmp', name)
    def resolution_dir = File.join(tmp_dir, 'author_resolution')
    def alias_dir = File.join(tmp_dir, 'alias_verification')
    def retry_evidence_file = File.join(tmp_dir, 'retry_evidence.json')
  end
end
