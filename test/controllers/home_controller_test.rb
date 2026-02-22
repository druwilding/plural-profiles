require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "index requires authentication" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "index shows home page when logged in" do
    sign_in_as users(:one)
    get root_path
    assert_response :success
    assert_match "Plural Profiles", response.body
  end

  test "index shows sidebar with user profiles and groups" do
    sign_in_as users(:one)
    get root_path
    assert_response :success
    assert_match "Alice", response.body
    assert_match "Friends", response.body
  end
end
