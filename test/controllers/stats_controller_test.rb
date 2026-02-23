require "test_helper"

class StatsControllerTest < ActionDispatch::IntegrationTest
  test "shows stats without authentication" do
    get stats_path
    assert_response :success
    assert_select "h1", "Stats"
    assert_select ".stats-card", 4
  end
end
