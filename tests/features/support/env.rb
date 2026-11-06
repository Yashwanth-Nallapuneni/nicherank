# Cucumber setup: Rails + Capybara (rack_test, no JS) + transactional cleanup per scenario.
# cucumber-rails assumes features/ sits at the Rails root; ours is under tests/.
ENV["RAILS_ROOT"] ||= File.expand_path("../../..", __dir__)
require "cucumber/rails"
require_relative "../../spec/support/test_database"
require_relative "../../spec/support/ranking_helpers"

ActionController::Base.allow_rescue = false
DatabaseCleaner.strategy = :transaction
Cucumber::Rails::Database.javascript_strategy = :truncation

World(RankingHelpers)
