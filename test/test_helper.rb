if ENV["COVERAGE"] == "1"
  require "simplecov"

  SimpleCov.start "rails" do
    add_filter "/test/"
  end
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "rspec/mocks/standalone"

module ActiveSupport
  class TestCase
    # SQLite in test can be unstable with threaded parallel tests on Windows.
    workers = ENV.fetch("TEST_WORKERS", "1").to_i
    parallelize(workers: workers, with: :threads) if workers > 1

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Include RSpec::Mocks to provide `double` helper  
    include RSpec::Mocks::ExampleMethods

    # Add more helper methods to be used by all tests here...
  end
end
