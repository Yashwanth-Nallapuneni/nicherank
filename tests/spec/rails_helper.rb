require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "capybara/rspec"
require_relative "support/test_database"

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  # Story 8 (country/region) is deferred: all ten universities are in the US.
  config.filter_run_excluding requires_location_metadata: true
end
