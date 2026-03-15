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

  test "panel returns profile content fragment" do
    group = groups(:friends)
    profile = profiles(:alice)
    get panel_group_profile_path(group_uuid: group.uuid, uuid: profile.uuid)
    assert_response :success
    assert_match "Alice", response.body
    # Should be a fragment, not a full page
    assert_no_match "<!DOCTYPE", response.body
  end

  test "panel returns 404 for profile not in group" do
    group = groups(:friends)
    carol = profiles(:carol)
    get panel_group_profile_path(group_uuid: group.uuid, uuid: carol.uuid)
    assert_response :not_found
  end

  test "show finds descendant profile through root group context" do
    alpha = groups(:alpha_clan)
    ember = profiles(:ember) # in prism_circle, descendant of alpha via spectrum
    get group_profile_path(group_uuid: alpha.uuid, uuid: ember.uuid)
    assert_response :success
    assert_match "Ember", response.body
    assert_match "Back to Alpha Clan", response.body
  end

  test "show returns 404 for profile hidden by inclusion override" do
    castle = groups(:castle_clan)
    drift = profiles(:drift) # in flux, but include_direct_profiles is false on castle→flux edge
    get group_profile_path(group_uuid: castle.uuid, uuid: drift.uuid)
    assert_response :not_found
  end

  test "panel finds descendant profile through root group context" do
    alpha = groups(:alpha_clan)
    ember = profiles(:ember)
    get panel_group_profile_path(group_uuid: alpha.uuid, uuid: ember.uuid)
    assert_response :success
    assert_match "Ember", response.body
  end

  test "panel returns 404 for profile hidden by inclusion override" do
    castle = groups(:castle_clan)
    drift = profiles(:drift)
    get panel_group_profile_path(group_uuid: castle.uuid, uuid: drift.uuid)
    assert_response :not_found
  end

  test "show applies group theme CSS when group has a theme" do
    group = groups(:friends) # has theme: dark_forest
    profile = profiles(:alice)
    get group_profile_path(group_uuid: group.uuid, uuid: profile.uuid)
    assert_response :success
    # dark_forest theme has --page-bg: #0e2e24 — should appear in body style
    assert_match "--page-bg: #0e2e24", response.body
  end

  test "show uses site default CSS when group has no theme" do
    group = groups(:everyone)
    profile = profiles(:alice)
    get group_profile_path(group_uuid: group.uuid, uuid: profile.uuid)
    assert_response :success
    # default_shared theme has --page-bg: #1a1a2e
    assert_match "--page-bg: #1a1a2e", response.body
  end
end
