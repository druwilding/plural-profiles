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

  # -- Admin badge --

  test "admin link is present for admin user" do
    sign_in_as users(:one)
    assert users(:one).admin?
    get root_path
    assert_select ".site-header nav a[href=?]", admin_root_path, text: "Admin"
  end

  test "admin link is absent for non-admin user" do
    sign_in_as users(:two)
    assert_not users(:two).admin?
    get root_path
    assert_select "a[href=?]", admin_root_path, count: 0
  end
end
