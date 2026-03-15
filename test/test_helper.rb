ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

if ENV["CI"].present?
  require "minitest/reporters"
  require "minitest/minitest_reporter_plugin"
  Minitest::Reporters.use!(
    [
      Minitest::Reporters::DefaultReporter.new(color: true),
      Minitest::Reporters::HtmlReporter.new(reports_dir: "test/reports")
    ],
    ENV,
    Minitest.backtrace_filter
  )
  Minitest.extensions << "minitest_reporter" unless Minitest.extensions.include?("minitest_reporter")
end
