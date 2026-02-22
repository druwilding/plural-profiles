require "test_helper"

class GroupProfilesControllerTest < ActionDispatch::IntegrationTest
  test "show displays profile within group context" do
    group = groups(:friends)
    profile = profiles(:alice)
    get group_profile_path(group_uuid: group.uuid, uuid: profile.uuid)
    assert_response :success
    assert_match "Alice", response.body
  end

  test "show returns 404 for profile not in group" do
    group = groups(:friends)
    carol = profiles(:carol) # carol is not in the friends group
    get group_profile_path(group_uuid: group.uuid, uuid: carol.uuid)
    assert_response :not_found
  end

  test "show returns 404 for unknown group" do
    get group_profile_path(group_uuid: "nonexistent", uuid: profiles(:alice).uuid)
    assert_response :not_found
  end

  test "show works when logged in" do
    sign_in_as users(:one)
    group = groups(:friends)
    profile = profiles(:alice)
    get group_profile_path(group_uuid: group.uuid, uuid: profile.uuid)
    assert_response :success
  end
end
