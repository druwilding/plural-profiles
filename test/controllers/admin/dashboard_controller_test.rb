require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "non-admins are redirected" do
    sign_in_as users(:two)
    get admin_root_path
    assert_redirected_to root_path
  end

  test "links to each admin area" do
    sign_in_as users(:one)
    get admin_root_path

    assert_response :success
    assert_select "a[href=?]", admin_emotes_path, text: "Emotes"
    assert_select "a[href=?]", admin_emote_sets_path, text: "Emote sets"
  end
end
