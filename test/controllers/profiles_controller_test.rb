require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "show displays public profile by uuid" do
    profile = profiles(:alice)
    get profile_path(uuid: profile.uuid)
    assert_response :success
    assert_match "Alice", response.body
  end

  test "show works when logged in" do
    sign_in_as users(:one)
    profile = profiles(:alice)
    get profile_path(uuid: profile.uuid)
    assert_response :success
  end

  test "show returns 404 for unknown uuid" do
    get profile_path(uuid: "nonexistent-uuid")
    assert_response :not_found
  end

  test "show displays heart emojis on public profile" do
    profile = profiles(:alice)
    profile.update!(heart_emojis: %w[36_red_heart 22_violet_heart])
    get profile_path(uuid: profile.uuid)
    assert_response :success
    assert_match "Heart emojis", response.body
    assert_match "36_red_heart.webp", response.body
  end

  test "show does not display heart section when none selected" do
    profile = profiles(:alice)
    profile.update!(heart_emojis: [])
    get profile_path(uuid: profile.uuid)
    assert_response :success
    assert_no_match "Heart emojis", response.body
  end
end
