require "test_helper"

class GroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "show displays public group by uuid" do
    group = groups(:friends)
    get group_path(uuid: group.uuid)
    assert_response :success
    assert_match "Friends", response.body
  end

  test "show displays the group's emotes on the shared page, even without pronouns" do
    group = groups(:friends)
    group.update!(pronouns: nil, emotes: ":aqua_heart: :aqua_heart:")
    get group_path(uuid: group.uuid)
    assert_response :success
    assert_equal [ "aqua heart", "aqua heart" ], css_select(".pronouns__emotes img").map { |img| img["alt"] }.first(2)
  end

  test "show lists group profiles" do
    group = groups(:friends)
    get group_path(uuid: group.uuid)
    assert_response :success
    assert_match "Alice", response.body
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

  test "show renders direct child group cards in the content panel" do
    alpha = groups(:alpha_clan)
    get group_path(uuid: alpha.uuid)
    assert_response :success
    # Echo Shard and Spectrum are direct children — should appear as group cards
    assert_select "[data-action='click->tree#selectGroup'][data-group-uuid='#{groups(:echo_shard).uuid}']" do
      assert_select "h3", text: "Echo Shard"
    end
    assert_select "[data-action='click->tree#selectGroup'][data-group-uuid='#{groups(:spectrum).uuid}']" do
      assert_select "h3", text: "Spectrum"
    end
  end

  test "show does not render grandchild groups as direct cards" do
    alpha = groups(:alpha_clan)
    get group_path(uuid: alpha.uuid)
    assert_response :success
    # Prism Circle is a grandchild, not a direct child — must not appear as a card in root content
    assert_select ".explorer__content [data-action='click->tree#selectGroup'][data-group-uuid='#{groups(:prism_circle).uuid}']", count: 0
  end

  test "panel returns direct child group cards" do
    alpha = groups(:alpha_clan)
    get panel_group_path(uuid: alpha.uuid)
    assert_response :success
    assert_select "[data-action='click->tree#selectGroup'][data-group-uuid='#{groups(:echo_shard).uuid}']"
    assert_select "[data-action='click->tree#selectGroup'][data-group-uuid='#{groups(:spectrum).uuid}']"
  end

  test "panel returns child group cards when reached via path" do
    flux = groups(:flux)
    castle = groups(:castle_clan)
    get panel_group_path(uuid: flux.uuid, root: castle.uuid, path: [ flux.id ])
    assert_response :success
    # Echo Shard is a child of Flux and not hidden
    assert_select "[data-action='click->tree#selectGroup'][data-group-uuid='#{groups(:echo_shard).uuid}']"
  end

  test "panel hides child groups with a path-scoped override" do
    flux = groups(:flux)
    castle = groups(:castle_clan)
    get panel_group_path(uuid: flux.uuid, root: castle.uuid, path: [ flux.id ])
    assert_response :success
    # Static Burst is hidden in Flux when reached via Castle Clan
    assert_select "[data-action='click->tree#selectGroup'][data-group-uuid='#{groups(:static_burst).uuid}']", count: 0
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

  test "requires authentication" do
    sign_out
    get group_path(uuid: groups(:friends).uuid)
    assert_redirected_to new_session_path
  end

  test "panel requires authentication" do
    sign_out
    get panel_group_path(uuid: groups(:friends).uuid)
    assert_redirected_to new_session_path
  end
end
