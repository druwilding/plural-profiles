require "test_helper"

class GroupsControllerTest < ActionDispatch::IntegrationTest
  test "show displays public group by uuid" do
    group = groups(:friends)
    get group_path(uuid: group.uuid)
    assert_response :success
    assert_match "Friends", response.body
  end

  test "show lists group profiles" do
    group = groups(:friends)
    get group_path(uuid: group.uuid)
    assert_response :success
    assert_match "Alice", response.body
  end

  test "show works when logged in" do
    sign_in_as users(:one)
    group = groups(:friends)
    get group_path(uuid: group.uuid)
    assert_response :success
  end

  test "show returns 404 for unknown uuid" do
    get group_path(uuid: "nonexistent-uuid")
    assert_response :not_found
  end

  test "show displays sub-groups in tree sidebar" do
    everyone = groups(:everyone)
    get group_path(uuid: everyone.uuid)
    assert_response :success
    assert_match "Friends", response.body
    # Explorer layout should be present
    assert_select ".explorer"
    assert_select ".explorer__sidebar"
    assert_select ".explorer__content"
  end

  test "show includes profiles from sub-groups" do
    everyone = groups(:everyone)
    get group_path(uuid: everyone.uuid)
    assert_response :success
    # Alice is in friends, which is a child of everyone
    assert_match "Alice", response.body
  end

  test "show recurses deeply into nested sub-groups" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)

    # Build: everyone → friends → close_friends → alice
    close_friends = user.groups.create!(name: "Close Friends")
    GroupGroup.create!(parent_group: friends, child_group: close_friends)
    close_friends.profiles << profiles(:alice)

    get group_path(uuid: everyone.uuid)
    assert_response :success
    assert_match "Close Friends", response.body
    assert_match "Alice", response.body
  end

  test "show displays sub-group profiles under their own group" do
    everyone = groups(:everyone)

    get group_path(uuid: everyone.uuid)
    assert_response :success
    # Alice appears in the tree under Friends, with Friends' group UUID
    assert_select "a[data-group-uuid='#{groups(:friends).uuid}'][data-profile-uuid='#{profiles(:alice).uuid}']"
  end

  test "show renders empty state when no profiles or sub-groups" do
    user = users(:one)
    empty_group = user.groups.create!(name: "Empty")
    get group_path(uuid: empty_group.uuid)
    assert_response :success
    assert_no_match "No profiles in this group yet", response.body
  end

  test "show renders tree with direct profiles at root level" do
    friends = groups(:friends)
    get group_path(uuid: friends.uuid)
    assert_response :success
    # Alice is a direct profile — should appear in tree and content
    assert_match "Alice", response.body
  end

  test "panel returns group content fragment" do
    group = groups(:friends)
    get panel_group_path(uuid: group.uuid)
    assert_response :success
    assert_match "Friends", response.body
    assert_match "Alice", response.body
    # Should be a fragment, not a full page
    assert_no_match "<!DOCTYPE", response.body
  end

  test "panel returns 404 for unknown group" do
    get panel_group_path(uuid: "nonexistent-uuid")
    assert_response :not_found
  end

  test "panel hides profiles with a matching path-scoped override" do
    flux = groups(:flux)
    castle_clan = groups(:castle_clan)
    # Override hides Drift and Ripple in Flux when reached as a direct child of Castle Clan
    get panel_group_path(uuid: flux.uuid, root: castle_clan.uuid, path: [ flux.id ])
    assert_response :success
    assert_no_match "Drift", response.body
    assert_no_match "Ripple", response.body
  end

  test "panel shows profiles when path does not match any override" do
    flux = groups(:flux)
    castle_clan = groups(:castle_clan)
    # Different path (e.g. empty — reached as if it were the root) has no override
    get panel_group_path(uuid: flux.uuid, root: castle_clan.uuid, path: [])
    assert_response :success
    assert_match "Drift", response.body
    assert_match "Ripple", response.body
  end

  test "show applies group theme CSS when group has a theme" do
    group = groups(:friends) # has theme: dark_forest
    get group_path(uuid: group.uuid)
    assert_response :success
    # dark_forest theme has --page-bg: #0e2e24 — should appear in body style
    assert_match "--page-bg: #0e2e24", response.body
  end

  test "show uses site default CSS when group has no theme" do
    group = groups(:everyone) # no theme in fixture
    get group_path(uuid: group.uuid)
    assert_response :success
    # default_shared theme has --page-bg: #1a1a2e
    assert_match "--page-bg: #1a1a2e", response.body
  end
end
