require "test_helper"

class Our::GroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other_user = users(:two)
    @group = groups(:friends)
  end

  # -- Authenticated happy paths --

  test "index lists current user groups" do
    sign_in_as @user
    get our_groups_path
    assert_response :success
    assert_match "Friends", response.body
    assert_no_match "Family", response.body
  end

  test "show displays own group" do
    sign_in_as @user
    get our_group_path(@group)
    assert_response :success
    assert_match "Friends", response.body
  end

  test "new renders form" do
    sign_in_as @user
    get new_our_group_path
    assert_response :success
  end

  test "new form includes Our themes optgroup when user has personal themes" do
    sign_in_as @user
    get new_our_group_path
    assert_select "select[name='group[theme_id]'] optgroup[label='Our themes']"
    doc = Nokogiri::HTML(response.body)
    our_themes_optgroup = doc.at_css("select[name='group[theme_id]'] optgroup[label='Our themes']")
    option_values = our_themes_optgroup.css("option").map { |opt| opt["value"].to_i }
    all_theme_ids = Theme.where(user: @user).pluck(:id)
    assert_equal all_theme_ids.sort, option_values.sort, "'Our themes' optgroup should include all user themes (personal and shared)"
  end

  test "new form includes Shared themes optgroup when shared themes exist" do
    sign_in_as @user
    get new_our_group_path
    assert_select "select[name='group[theme_id]'] optgroup[label='Shared themes']"
  end

  test "edit form preserves selected theme" do
    sign_in_as @user
    @group.update!(theme: themes(:dark_forest))
    get edit_our_group_path(@group)
    assert_select "select[name='group[theme_id]'] option[selected][value='#{themes(:dark_forest).id}']"
  end

  test "create saves a valid group" do
    sign_in_as @user
    assert_difference("Group.count", 1) do
      post our_groups_path, params: {
        group: { name: "Coworkers", description: "People we work with." }
      }
    end
    assert_redirected_to our_group_path(Group.last)
    follow_redirect!
    assert_match "Group created.", response.body
  end

  test "create rejects blank name" do
    sign_in_as @user
    assert_no_difference("Group.count") do
      post our_groups_path, params: {
        group: { name: "", description: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "edit renders form for own group" do
    sign_in_as @user
    get edit_our_group_path(@group)
    assert_response :success
  end

  test "update changes group attributes" do
    sign_in_as @user
    patch our_group_path(@group), params: {
      group: { name: "Best Friends" }
    }
    assert_redirected_to our_group_path(@group)
    follow_redirect!
    assert_match "Group updated.", response.body
    assert_equal "Best Friends", @group.reload.name
  end

  test "update with avatar upload" do
    sign_in_as @user
    patch our_group_path(@group), params: {
      group: {
        avatar: fixture_file_upload("avatar.png", "image/png"),
        avatar_alt_text: "Group photo"
      }
    }
    assert_redirected_to our_group_path(@group)
    assert @group.reload.avatar.attached?
    assert_equal "Group photo", @group.avatar_alt_text
  end

  test "update with remove_avatar purges avatar" do
    sign_in_as @user
    @group.avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert @group.avatar.attached?

    patch our_group_path(@group), params: {
      group: { name: @group.name, remove_avatar: "1" }
    }
    assert_redirected_to our_group_path(@group)
    assert_not @group.reload.avatar.attached?
  end

  test "update rejects non-image avatar" do
    sign_in_as @user
    patch our_group_path(@group), params: {
      group: {
        name: @group.name,
        avatar: Rack::Test::UploadedFile.new(StringIO.new("<script>alert('xss')</script>"), "text/html", false, original_filename: "evil.html")
      }
    }
    assert_response :unprocessable_entity
    assert_not @group.reload.avatar.attached?
  end

  test "destroy deletes group" do
    sign_in_as @user
    assert_difference("Group.count", -1) do
      delete our_group_path(@group)
    end
    assert_redirected_to our_groups_path
  end

  test "update sets created_at to a past timestamp" do
    sign_in_as @user
    past = 1.year.ago.utc
    patch our_group_path(@group), params: {
      group: { created_at: past.strftime("%Y-%m-%dT%H:%M") }
    }
    assert_redirected_to our_group_path(@group)
    assert_in_delta past.to_i, @group.reload.created_at.to_i, 60
  end

  test "update rejects a created_at value in the future" do
    sign_in_as @user
    future = 1.day.from_now.utc
    patch our_group_path(@group), params: {
      group: { created_at: future.strftime("%Y-%m-%dT%H:%M") }
    }
    assert_response :unprocessable_entity
    assert_match "can&#39;t be in the future", response.body
  end

  test "update with malformed created_at does not raise" do
    sign_in_as @user
    original_created_at = @group.created_at
    patch our_group_path(@group), params: {
      group: { name: @group.name, created_at: "not-a-date" }
    }
    # Malformed value is stripped in group_params — update succeeds and
    # created_at is left unchanged.
    assert_redirected_to our_group_path(@group)
    assert_in_delta original_created_at.to_i, @group.reload.created_at.to_i, 1
  end

  # -- Manage profiles --

  test "manage_profiles shows available profiles" do
    sign_in_as @user
    get manage_profiles_our_group_path(@group)
    assert_response :success
    # Bob is not in the friends group, so should appear as available
    assert_match "Bob", response.body
  end

  test "add_profile adds a profile to the group" do
    sign_in_as @user
    bob = profiles(:bob)
    assert_not_includes @group.profiles, bob

    assert_difference("GroupProfile.count", 1) do
      post add_profile_our_group_path(@group), params: { profile_id: bob.id }
    end
    assert_redirected_to manage_profiles_our_group_path(@group)
    assert_includes @group.reload.profiles, bob
  end

  test "remove_profile removes a profile from the group" do
    sign_in_as @user
    alice = profiles(:alice)
    assert_includes @group.profiles, alice

    assert_difference("GroupProfile.count", -1) do
      delete remove_profile_our_group_path(@group), params: { profile_id: alice.id }
    end
    assert_redirected_to manage_profiles_our_group_path(@group)
    assert_not_includes @group.reload.profiles, alice
  end

  # -- Manage groups (sub-groups) --

  test "add_group adds a sub-group" do
    sign_in_as @user
    everyone = groups(:everyone)
    new_group = @user.groups.create!(name: "Coworkers")

    assert_difference("GroupGroup.count", 1) do
      post add_group_our_group_path(everyone), params: { group_id: new_group.id }
    end
    assert_redirected_to manage_groups_our_group_path(everyone)
    assert_includes everyone.reload.child_groups, new_group
  end

  test "add_group rejects circular reference" do
    sign_in_as @user
    everyone = groups(:everyone)
    # friends → everyone would be circular (everyone → friends exists)
    assert_no_difference("GroupGroup.count") do
      post add_group_our_group_path(@group), params: { group_id: everyone.id }
    end
    assert_redirected_to manage_groups_our_group_path(@group)
    follow_redirect!
    assert_match "circular", response.body
  end

  test "remove_group removes a sub-group" do
    sign_in_as @user
    everyone = groups(:everyone)
    assert_includes everyone.child_groups, @group

    assert_difference("GroupGroup.count", -1) do
      delete remove_group_our_group_path(everyone), params: { group_id: @group.id }
    end
    assert_redirected_to manage_groups_our_group_path(everyone)
    assert_not_includes everyone.reload.child_groups, @group
  end

  # -- Edge case: logged out user gets redirected to public --

  test "show redirects logged-out user to public group" do
    get our_group_path(@group)
    assert_redirected_to group_path(@group.uuid)
  end

  test "index redirects logged-out user to sign in" do
    get our_groups_path
    assert_redirected_to new_session_path
  end

  test "new redirects logged-out user to sign in" do
    get new_our_group_path
    assert_redirected_to new_session_path
  end

  test "create redirects logged-out user to sign in" do
    post our_groups_path, params: { group: { name: "Nope" } }
    assert_redirected_to new_session_path
  end

  test "edit redirects logged-out user to sign in" do
    get edit_our_group_path(@group)
    assert_redirected_to new_session_path
  end

  test "update redirects logged-out user to sign in" do
    patch our_group_path(@group), params: { group: { name: "Nope" } }
    assert_redirected_to new_session_path
  end

  test "destroy redirects logged-out user to sign in" do
    delete our_group_path(@group)
    assert_redirected_to new_session_path
  end

  test "manage_profiles redirects logged-out user to sign in" do
    get manage_profiles_our_group_path(@group)
    assert_redirected_to new_session_path
  end

  test "add_profile redirects logged-out user to sign in" do
    assert_no_difference("GroupProfile.count") do
      post add_profile_our_group_path(@group), params: { profile_id: profiles(:alice).id }
    end
    assert_redirected_to new_session_path
  end

  test "remove_profile redirects logged-out user to sign in" do
    assert_no_difference("GroupProfile.count") do
      delete remove_profile_our_group_path(@group), params: { profile_id: profiles(:alice).id }
    end
    assert_redirected_to new_session_path
  end

  test "add_group redirects logged-out user to sign in" do
    assert_no_difference("GroupGroup.count") do
      post add_group_our_group_path(@group), params: { group_id: groups(:everyone).id }
    end
    assert_redirected_to new_session_path
  end

  test "remove_group redirects logged-out user to sign in" do
    everyone = groups(:everyone)
    assert_no_difference("GroupGroup.count") do
      delete remove_group_our_group_path(everyone), params: { group_id: @group.id }
    end
    assert_redirected_to new_session_path
  end

  # -- Edge case: wrong user gets redirected to public --

  test "show redirects wrong user to public group" do
    sign_in_as @other_user
    get our_group_path(@group)
    assert_redirected_to group_path(@group.uuid)
    follow_redirect!
    assert_response :success
    assert_match "Friends", response.body
    assert_no_match "Edit", response.body
    assert_no_match "Delete", response.body
    assert_no_match "Manage profiles", response.body
  end

  test "edit redirects wrong user to public group" do
    sign_in_as @other_user
    get edit_our_group_path(@group)
    assert_redirected_to group_path(@group.uuid)
  end

  test "update redirects wrong user to public group" do
    sign_in_as @other_user
    patch our_group_path(@group), params: { group: { name: "Hacked" } }
    assert_redirected_to group_path(@group.uuid)
    assert_equal "Friends", @group.reload.name
  end

  test "destroy redirects wrong user to public group" do
    sign_in_as @other_user
    assert_no_difference("Group.count") do
      delete our_group_path(@group)
    end
    assert_redirected_to group_path(@group.uuid)
  end

  test "manage_profiles redirects wrong user to public group" do
    sign_in_as @other_user
    get manage_profiles_our_group_path(@group)
    assert_redirected_to group_path(@group.uuid)
  end

  test "add_profile redirects wrong user to public group" do
    sign_in_as @other_user
    assert_no_difference("GroupProfile.count") do
      post add_profile_our_group_path(@group), params: { profile_id: profiles(:alice).id }
    end
    assert_redirected_to group_path(@group.uuid)
  end

  test "remove_profile redirects wrong user to public group" do
    sign_in_as @other_user
    assert_no_difference("GroupProfile.count") do
      delete remove_profile_our_group_path(@group), params: { profile_id: profiles(:alice).id }
    end
    assert_redirected_to group_path(@group.uuid)
  end

  test "add_group redirects wrong user to public group" do
    sign_in_as @other_user
    assert_no_difference("GroupGroup.count") do
      post add_group_our_group_path(@group), params: { group_id: groups(:everyone).id }
    end
    assert_redirected_to group_path(@group.uuid)
  end

  test "remove_group redirects wrong user to public group" do
    sign_in_as @other_user
    everyone = groups(:everyone)
    assert_no_difference("GroupGroup.count") do
      delete remove_group_our_group_path(everyone), params: { group_id: @group.id }
    end
    assert_redirected_to group_path(everyone.uuid)
  end

  # -- regenerate_uuid --

  test "regenerate_uuid changes the uuid and redirects with notice" do
    sign_in_as @user
    old_uuid = @group.uuid
    patch regenerate_uuid_our_group_path(@group)
    assert_redirected_to our_group_path(@group.reload)
    assert_not_equal old_uuid, @group.uuid
    follow_redirect!
    assert_match "Share URL regenerated.", response.body
  end

  test "regenerate_uuid does not contain the digit 7" do
    sign_in_as @user
    patch regenerate_uuid_our_group_path(@group)
    assert_no_match(/7/, @group.reload.uuid)
  end

  test "regenerate_uuid redirects logged-out user to sign in" do
    patch regenerate_uuid_our_group_path(@group)
    assert_redirected_to new_session_path
    assert_equal groups(:friends).uuid, @group.reload.uuid
  end

  test "regenerate_uuid redirects wrong user to public group" do
    sign_in_as @other_user
    old_uuid = @group.uuid
    patch regenerate_uuid_our_group_path(@group)
    assert_redirected_to group_path(@group.uuid)
    assert_equal old_uuid, @group.reload.uuid
  end

  # -- Manage groups --

  test "manage_groups renders for group with children" do
    user_three = users(:three)
    sign_in_as user_three
    alpha = groups(:alpha_clan)
    get manage_groups_our_group_path(alpha)
    assert_response :success
    assert_match "Manage groups in", response.body
    assert_match "Spectrum", response.body
  end

  test "manage_groups renders for group without children" do
    sign_in_as @user
    # Friends has no child groups, but has Alice as a direct profile.
    # The tree editor renders with root profiles.
    get manage_groups_our_group_path(@group)
    assert_response :success
    assert_match "Manage groups in", response.body
    assert_match "Alice", response.body
  end

  test "manage_groups requires authentication" do
    alpha = groups(:alpha_clan)
    get manage_groups_our_group_path(alpha)
    assert_redirected_to new_session_path
  end

  # -- toggle_visibility --

  test "toggle_visibility hides a group" do
    user_three = users(:three)
    sign_in_as user_three
    alpha = groups(:alpha_clan)
    spectrum = groups(:spectrum)
    prism = groups(:prism_circle)

    # Create a new override to hide Prism Circle at [spectrum]
    assert_difference("InclusionOverride.count", 1) do
      patch toggle_visibility_our_group_path(alpha), params: {
        target_type: "Group",
        target_id: prism.id,
        path: [ spectrum.id ].to_json,
        hidden: "1"
      }
    end
    assert_redirected_to manage_groups_our_group_path(alpha)
  end

  test "toggle_visibility shows a previously hidden group" do
    user_three = users(:three)
    sign_in_as user_three
    alpha = groups(:alpha_clan)
    spectrum = groups(:spectrum)
    prism = groups(:prism_circle)
    rogue = groups(:rogue_pack)

    # Rogue Pack is hidden at [spectrum, prism_circle] via fixture
    override = InclusionOverride.find_by(
      group: alpha, target_type: "Group", target_id: rogue.id
    )
    assert_not_nil override, "Fixture override should exist"

    assert_difference("InclusionOverride.count", -1) do
      patch toggle_visibility_our_group_path(alpha), params: {
        target_type: "Group",
        target_id: rogue.id,
        path: [ spectrum.id, prism.id ].to_json,
        hidden: "0"
      }
    end
    assert_redirected_to manage_groups_our_group_path(alpha)
  end

  test "toggle_visibility hides a profile" do
    user_three = users(:three)
    sign_in_as user_three
    alpha = groups(:alpha_clan)
    spectrum = groups(:spectrum)
    prism = groups(:prism_circle)
    ember = profiles(:ember)

    assert_difference("InclusionOverride.count", 1) do
      patch toggle_visibility_our_group_path(alpha), params: {
        target_type: "Profile",
        target_id: ember.id,
        path: [ spectrum.id, prism.id ].to_json,
        hidden: "1"
      }
    end
    assert_redirected_to manage_groups_our_group_path(alpha)
  end

  test "toggle_visibility shows a previously hidden profile" do
    user_three = users(:three)
    sign_in_as user_three
    castle = groups(:castle_clan)
    flux = groups(:flux)
    drift = profiles(:drift)

    # Drift is hidden at [flux] via fixture
    override = InclusionOverride.find_by(
      group: castle, target_type: "Profile", target_id: drift.id
    )
    assert_not_nil override, "Drift override should exist"

    assert_difference("InclusionOverride.count", -1) do
      patch toggle_visibility_our_group_path(castle), params: {
        target_type: "Profile",
        target_id: drift.id,
        path: [ flux.id ].to_json,
        hidden: "0"
      }
    end
    assert_redirected_to manage_groups_our_group_path(castle)
  end

  test "toggle_visibility hides a root-level profile (empty path)" do
    sign_in_as @user
    everyone = groups(:everyone)
    # Add Alice as a direct profile of Everyone
    everyone.profiles << profiles(:alice) unless everyone.profiles.include?(profiles(:alice))

    assert_difference("InclusionOverride.count", 1) do
      patch toggle_visibility_our_group_path(everyone), params: {
        target_type: "Profile",
        target_id: profiles(:alice).id,
        path: [].to_json,
        hidden: "1"
      }
    end
    assert_redirected_to manage_groups_our_group_path(everyone)
  end

  test "toggle_visibility rejects invalid target type" do
    user_three = users(:three)
    sign_in_as user_three
    alpha = groups(:alpha_clan)

    assert_no_difference("InclusionOverride.count") do
      patch toggle_visibility_our_group_path(alpha), params: {
        target_type: "User",
        target_id: user_three.id,
        path: [].to_json,
        hidden: "1"
      }
    end
    assert_redirected_to manage_groups_our_group_path(alpha)
    follow_redirect!
    assert_match "Invalid target", response.body
  end

  test "toggle_visibility rejects target belonging to another user" do
    sign_in_as @user
    everyone = groups(:everyone)
    # Try to hide a profile belonging to user three
    ember = profiles(:ember)

    assert_no_difference("InclusionOverride.count") do
      patch toggle_visibility_our_group_path(everyone), params: {
        target_type: "Profile",
        target_id: ember.id,
        path: [].to_json,
        hidden: "1"
      }
    end
    assert_redirected_to manage_groups_our_group_path(everyone)
  end

  test "toggle_visibility rejects bad path" do
    user_three = users(:three)
    sign_in_as user_three
    alpha = groups(:alpha_clan)

    # Path with a group ID that's not in the tree
    assert_no_difference("InclusionOverride.count") do
      patch toggle_visibility_our_group_path(alpha), params: {
        target_type: "Group",
        target_id: groups(:spectrum).id,
        path: [ 999_999 ].to_json,
        hidden: "1"
      }
    end
    assert_redirected_to manage_groups_our_group_path(alpha)
  end

  test "toggle_visibility responds to JSON" do
    user_three = users(:three)
    sign_in_as user_three
    alpha = groups(:alpha_clan)
    spectrum = groups(:spectrum)
    prism = groups(:prism_circle)

    patch toggle_visibility_our_group_path(alpha, format: :json), params: {
      target_type: "Group",
      target_id: prism.id,
      path: [ spectrum.id ].to_json,
      hidden: "1"
    }
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal true, json["hidden"]
  end

  test "toggle_visibility is idempotent for hide" do
    user_three = users(:three)
    sign_in_as user_three
    alpha = groups(:alpha_clan)
    spectrum = groups(:spectrum)
    prism = groups(:prism_circle)
    rogue = groups(:rogue_pack)

    # Rogue Pack is already hidden at [spectrum, prism] — hiding again should not create duplicate
    assert_no_difference("InclusionOverride.count") do
      patch toggle_visibility_our_group_path(alpha), params: {
        target_type: "Group",
        target_id: rogue.id,
        path: [ spectrum.id, prism.id ].to_json,
        hidden: "1"
      }
    end
    assert_redirected_to manage_groups_our_group_path(alpha)
  end

  test "toggle_visibility is idempotent for show" do
    sign_in_as @user
    everyone = groups(:everyone)

    # No override exists — showing again should not raise
    assert_no_difference("InclusionOverride.count") do
      patch toggle_visibility_our_group_path(everyone), params: {
        target_type: "Group",
        target_id: groups(:friends).id,
        path: [].to_json,
        hidden: "0"
      }
    end
    assert_redirected_to manage_groups_our_group_path(everyone)
  end

  test "toggle_visibility redirects logged-out user to sign in" do
    alpha = groups(:alpha_clan)
    patch toggle_visibility_our_group_path(alpha), params: {
      target_type: "Group", target_id: groups(:spectrum).id,
      path: [].to_json, hidden: "1"
    }
    assert_redirected_to new_session_path
  end

  test "toggle_visibility redirects wrong user to public group" do
    sign_in_as @other_user
    alpha = groups(:alpha_clan)
    patch toggle_visibility_our_group_path(alpha), params: {
      target_type: "Group", target_id: groups(:spectrum).id,
      path: [].to_json, hidden: "1"
    }
    assert_redirected_to group_path(alpha.uuid)
  end

  # -- labels --

  test "create saves labels from comma-separated text" do
    sign_in_as @user
    post our_groups_path, params: {
      group: { name: "Labelled", labels_text: "safe, work" }
    }
    assert_redirected_to our_group_path(Group.last)
    assert_equal %w[safe work], Group.last.labels
  end

  test "update saves labels" do
    sign_in_as @user
    patch our_group_path(@group), params: {
      group: { labels_text: "close friends, family" }
    }
    assert_redirected_to our_group_path(@group)
    assert_equal [ "close friends", "family" ], @group.reload.labels
  end

  test "update clears labels with blank text" do
    sign_in_as @user
    @group.update!(labels: %w[safe work])
    patch our_group_path(@group), params: {
      group: { labels_text: "" }
    }
    assert_redirected_to our_group_path(@group)
    assert_equal [], @group.reload.labels
  end

  test "show displays labels on private page" do
    sign_in_as @user
    @group.update!(labels: %w[safe work])
    get our_group_path(@group)
    assert_response :success
    assert_match "safe", response.body
    assert_match "work", response.body
  end

  test "index displays labels on group cards" do
    sign_in_as @user
    @group.update!(labels: %w[safe])
    get our_groups_path
    assert_response :success
    assert_match "safe", response.body
  end

  test "labels do not appear on public group page" do
    sign_in_as @user
    @group.update!(labels: %w[safe work])
    get group_path(@group.uuid)
    assert_response :success
    assert_no_match "label-badge", response.body
  end

  # -- Label filtering --

  test "index shows all groups when no label filter applied" do
    sign_in_as @user
    @group.update!(labels: %w[close])
    get our_groups_path
    assert_response :success
    assert_match "Friends", response.body
    assert_match "Everyone", response.body
  end

  test "index filters groups by label" do
    sign_in_as @user
    @group.update!(labels: %w[close])
    everyone = groups(:everyone)
    everyone.update!(labels: %w[public])
    get our_groups_path(label: "close")
    assert_response :success
    assert_select ".main-content h3 a", text: "Friends"
    assert_select ".main-content h3 a", text: "Everyone", count: 0
  end

  # -- Theme dropdown --

  test "create with a personal theme_id saves the theme" do
    sign_in_as @user
    post our_groups_path, params: {
      group: { name: "Themed Group", theme_id: themes(:dark_forest).id }
    }
    assert_redirected_to our_group_path(Group.last)
    assert_equal themes(:dark_forest), Group.last.theme
  end

  test "create with a shared theme_id saves the theme" do
    sign_in_as @user
    post our_groups_path, params: {
      group: { name: "Themed Group", theme_id: themes(:ocean_shared).id }
    }
    assert_redirected_to our_group_path(Group.last)
    assert_equal themes(:ocean_shared), Group.last.theme
  end

  test "create with another user's non-shared theme_id is rejected" do
    sign_in_as @user
    assert_no_difference("Group.count") do
      post our_groups_path, params: {
        group: { name: "Themed Group", theme_id: themes(:other_user_theme).id }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update changes a group's theme" do
    sign_in_as @user
    patch our_group_path(@group), params: {
      group: { theme_id: themes(:ocean_shared).id }
    }
    assert_redirected_to our_group_path(@group)
    assert_equal themes(:ocean_shared), @group.reload.theme
  end

  test "update clears a group's theme when blank is submitted" do
    sign_in_as @user
    @group.update!(theme: themes(:dark_forest))
    patch our_group_path(@group), params: {
      group: { theme_id: "" }
    }
    assert_redirected_to our_group_path(@group)
    assert_nil @group.reload.theme
  end

  test "index filter returns no groups when no match" do
    sign_in_as @user
    @group.update!(labels: %w[close])
    get our_groups_path(label: "nonexistent")
    assert_response :success
    assert_select ".main-content .profile-grid", count: 0
  end

  test "index shows filter bar when labels exist" do
    sign_in_as @user
    @group.update!(labels: %w[close])
    get our_groups_path
    assert_response :success
    assert_match "filter-bar", response.body
    assert_match "close", response.body
  end

  test "index hides filter bar when no labels exist" do
    sign_in_as @user
    get our_groups_path
    assert_response :success
    assert_no_match "filter-bar", response.body
  end

  test "index shows clear filter link when label filter is active" do
    sign_in_as @user
    @group.update!(labels: %w[close])
    get our_groups_path(label: "close")
    assert_response :success
    assert_match "Clear filter", response.body
  end

  test "index does not show clear filter link without active filter" do
    sign_in_as @user
    @group.update!(labels: %w[close])
    get our_groups_path
    assert_response :success
    assert_no_match "Clear filter", response.body
  end

  # -- Duplication wizard (Phase 6) --

  test "duplicate renders label input form" do
    sign_in_as users(:three)
    group = groups(:echo_shard)
    get duplicate_our_group_path(group)
    assert_response :success
    assert_match "Duplicate #{group.name}", response.body
    assert_match group.name, response.body
  end

  test "duplicate_scan with empty labels returns error" do
    sign_in_as users(:three)
    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "" }
    assert_response :unprocessable_entity
    assert_match "at least one label", response.body
  end

  test "duplicate_scan with no conflicts redirects to confirm" do
    sign_in_as users(:three)
    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    assert_redirected_to duplicate_confirm_our_group_path(group)
  end

  test "duplicate_scan with conflicts redirects to resolve" do
    user = users(:three)
    sign_in_as user
    prism = groups(:prism_circle)
    user.groups.create!(name: "Prism Circle (blue)", copied_from: prism, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    assert_redirected_to duplicate_resolve_our_group_path(group)
  end

  test "duplicate_resolve shows conflict page" do
    user = users(:three)
    sign_in_as user
    prism = groups(:prism_circle)
    user.groups.create!(name: "Prism Circle (blue)", copied_from: prism, labels: [ "blue" ])

    group = groups(:echo_shard)
    # First set up wizard state
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    follow_redirect!

    assert_response :success
    assert_match "Group question 1", response.body
    assert_match prism.name, response.body
  end

  test "duplicate_resolve POST with missing resolution re-renders with alert" do
    user = users(:three)
    sign_in_as user
    prism = groups(:prism_circle)
    user.groups.create!(name: "Prism Circle (blue)", copied_from: prism, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }

    # Submit without selecting a radio button
    post duplicate_resolve_our_group_path(group), params: {}
    assert_response :unprocessable_entity
    assert_match "Please select an option before continuing.", response.body
    assert_match "Group question 1", response.body
  end

  test "duplicate_resolve POST with tampered resolution re-renders with alert" do
    user = users(:three)
    sign_in_as user
    prism = groups(:prism_circle)
    user.groups.create!(name: "Prism Circle (blue)", copied_from: prism, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }

    post duplicate_resolve_our_group_path(group), params: { resolution: "hacked" }
    assert_response :unprocessable_entity
    assert_match "Please select an option before continuing.", response.body
  end

  test "duplicate_resolve POST with reuse skips descendant conflicts" do
    user = users(:three)
    sign_in_as user
    prism = groups(:prism_circle)
    rogue = groups(:rogue_pack)
    user.groups.create!(name: "Prism Copy", copied_from: prism, labels: [ "blue" ])
    user.groups.create!(name: "Rogue Copy", copied_from: rogue, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    # Resolve prism as reuse — should skip rogue and go to confirm
    post duplicate_resolve_our_group_path(group), params: { resolution: "reuse" }
    assert_redirected_to duplicate_confirm_our_group_path(group)
  end

  test "duplicate_confirm shows summary page" do
    sign_in_as users(:three)
    group = groups(:echo_shard)
    # Set up wizard state with no conflicts
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    follow_redirect!
    assert_response :success
    assert_match "Confirm duplication", response.body
    assert_match group.name, response.body
  end

  test "duplicate_confirm shows tree with group and profile names" do
    sign_in_as users(:three)
    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    follow_redirect!
    assert_response :success

    # Root group should appear
    assert_match group.name, response.body
    # Child groups should appear in the tree
    assert_match groups(:prism_circle).name, response.body
    assert_match groups(:rogue_pack).name, response.body
    # Profiles should appear
    assert_match profiles(:mirage).name, response.body
    assert_match profiles(:ember).name, response.body
    assert_match profiles(:stray).name, response.body
  end

  test "duplicate_confirm shows new labels on tree items" do
    sign_in_as users(:three)
    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    follow_redirect!
    assert_response :success

    # The label "blue" should appear multiple times (root + tree items)
    assert response.body.scan("blue").length > 1, "Label 'blue' should appear on tree items"
  end

  test "duplicate_confirm shows new label on profiles inside directly-reused groups" do
    # Regression: inherited-reuse profile nodes (action=reuse, directly_reused=false)
    # were not showing the new label because the partial checked profile.labels
    # (empty on the original) instead of new_labels.
    #
    # Tree: Echo Shard → Prism Circle → Rogue Pack (reused) → Stray (inherited-reuse)
    # Stray is also a direct profile of Prism Circle (action=new → label shown correctly).
    # The bug only affected Stray's occurrence inside the reused Rogue Pack.
    user = users(:three)
    sign_in_as user
    rogue = groups(:rogue_pack)
    user.groups.create!(name: "Rogue Copy", copied_from: rogue, labels: [ "green" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "green" }
    # Rogue Pack has a conflict — resolve it as reuse
    post duplicate_resolve_our_group_path(group), params: { resolution: "reuse" }
    follow_redirect!
    assert_response :success

    # "green" badges expected (exact count; off-by-one would indicate the bug):
    #   intro card (1) + Echo Shard root (1) + Mirage/new (1) +
    #   Prism Circle/new (1) + Ember/new (1) + Stray-in-prism/new (1) +
    #   Rogue Pack/reuse via reuse_target (1) + Stray-in-rogue/inherited-reuse (1) = 8
    # Before the fix, Stray-in-rogue showed nothing → count was 7.
    badge_count = response.body.scan('<span class="label-badge">green</span>').length
    assert_equal 8, badge_count,
      "Expected 'green' label on all tree nodes including inherited-reuse profiles (Stray inside Rogue Pack), got #{badge_count}"
  end

  test "duplicate_confirm does not show reuse legend when no resolutions use reuse" do
    sign_in_as users(:three)
    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    follow_redirect!
    assert_response :success

    assert_no_match "existing copy", response.body
    assert_no_match "will be linked into the new tree", response.body
  end

  test "duplicate_confirm shows reuse legend and tags when resolutions include reuse" do
    user = users(:three)
    sign_in_as user
    prism = groups(:prism_circle)
    user.groups.create!(name: "Prism Copy", copied_from: prism, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    # Resolve prism as reuse
    post duplicate_resolve_our_group_path(group), params: { resolution: "reuse" }
    follow_redirect!
    assert_response :success

    assert_match "existing copy", response.body
    assert_match "will be linked into the new tree", response.body
  end

  test "duplicate_confirm shows hidden tag for items with inclusion overrides" do
    sign_in_as users(:three)
    # Castle Clan has overrides: static_burst hidden, drift hidden, ripple hidden
    group = groups(:castle_clan)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    follow_redirect!
    assert_response :success

    # The "hidden" tag should appear for the overridden items
    assert_match "hidden", response.body
    # Should be rendered using the tree-editor structure
    assert_match "tree-editor__tag--hidden", response.body
  end

  test "duplicate_confirm renders tree-editor structure" do
    sign_in_as users(:three)
    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    follow_redirect!
    assert_response :success

    # Should have tree-editor classes
    assert_match "tree-editor", response.body
    assert_match "tree-editor__folder--root", response.body
    assert_match "tree-editor__name", response.body
  end

  test "duplicate_confirm shows root profiles" do
    sign_in_as users(:three)
    # Echo Shard has mirage as a direct profile
    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    follow_redirect!
    assert_response :success

    assert_match profiles(:mirage).name, response.body
  end

  test "duplicate_execute creates the tree and redirects" do
    sign_in_as users(:three)
    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }

    assert_difference("Group.count", 3) do
      post duplicate_execute_our_group_path(group)
    end
    # Redirects to the newly created root group (the copy of echo_shard)
    new_root = Group.where(copied_from: group).where("labels @> ?", [ "blue" ].to_json).first
    assert_redirected_to our_group_path(new_root)
    follow_redirect!
    assert_match "Group duplicated", response.body
  end

  test "duplicate_execute clears session wizard state" do
    sign_in_as users(:three)
    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    post duplicate_execute_our_group_path(group)
    # Attempting to access confirm after execution should redirect to duplicate start
    get duplicate_confirm_our_group_path(group)
    assert_redirected_to duplicate_our_group_path(group)
  end

  test "duplicate requires authentication" do
    group = groups(:echo_shard)
    get duplicate_our_group_path(group)
    assert_redirected_to new_session_path
  end

  # -- Profile conflict resolution --

  test "duplicate_scan with profile conflicts redirects to resolve" do
    user = users(:three)
    sign_in_as user
    stray = profiles(:stray)
    user.profiles.create!(name: "Stray (blue)", copied_from: stray, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    assert_redirected_to duplicate_resolve_our_group_path(group)
  end

  test "duplicate_scan with only profile conflicts goes to profile phase" do
    user = users(:three)
    sign_in_as user
    stray = profiles(:stray)
    user.profiles.create!(name: "Stray (blue)", copied_from: stray, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    follow_redirect!

    assert_response :success
    assert_match "Profile question 1", response.body
    assert_match stray.name, response.body
  end

  test "duplicate_resolve shows profile conflict with pronouns" do
    user = users(:three)
    sign_in_as user
    stray = profiles(:stray)
    stray.update!(pronouns: "they/them")
    user.profiles.create!(name: "Stray (blue)", copied_from: stray, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    follow_redirect!

    assert_response :success
    assert_match "they/them", response.body
  end

  test "duplicate_resolve_post with profile reuse advances to confirm" do
    user = users(:three)
    sign_in_as user
    stray = profiles(:stray)
    user.profiles.create!(name: "Stray (blue)", copied_from: stray, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    # Should be on profile conflict phase
    post duplicate_resolve_our_group_path(group), params: { resolution: "reuse" }
    assert_redirected_to duplicate_confirm_our_group_path(group)
  end

  test "duplicate_scan with both group and profile conflicts resolves groups first" do
    user = users(:three)
    sign_in_as user
    rogue = groups(:rogue_pack)
    stray = profiles(:stray)
    user.groups.create!(name: "Rogue Copy", copied_from: rogue, labels: [ "blue" ])
    user.profiles.create!(name: "Stray Copy", copied_from: stray, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    follow_redirect!

    assert_response :success
    assert_match "Group question 1", response.body
    assert_match rogue.name, response.body
  end

  test "duplicate group conflict reuse auto-resolves profile conflicts in reused subtree" do
    user = users(:three)
    sign_in_as user
    prism = groups(:prism_circle)
    stray = profiles(:stray)
    user.groups.create!(name: "Prism Copy", copied_from: prism, labels: [ "blue" ])
    user.profiles.create!(name: "Stray Copy", copied_from: stray, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }

    # Resolve prism as reuse — Stray is in prism_circle and rogue_pack which are both
    # in the reused subtree, but also in echo_shard? No — Stray is not directly in echo_shard.
    # Stray is in prism_circle and rogue_pack, both descendants of prism, so all reused.
    post duplicate_resolve_our_group_path(group), params: { resolution: "reuse" }
    # Should go to confirm (profile conflict auto-resolved)
    assert_redirected_to duplicate_confirm_our_group_path(group)
  end

  test "duplicate_execute with profile reuse reuses the existing profile copy" do
    user = users(:three)
    sign_in_as user
    stray = profiles(:stray)
    stray_copy = user.profiles.create!(name: "Stray (blue)", copied_from: stray, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    # Resolve stray as reuse
    post duplicate_resolve_our_group_path(group), params: { resolution: "reuse" }

    initial_profile_count = Profile.count
    post duplicate_execute_our_group_path(group)

    # Stray was reused, Mirage and Ember were freshly copied = 2 new profiles
    assert_equal initial_profile_count + 2, Profile.count

    # The reused stray copy should still be the only one
    stray_copies = Profile.where(copied_from: stray).where("labels @> ?", [ "blue" ].to_json)
    assert_equal 1, stray_copies.count
    assert_equal stray_copy.id, stray_copies.first.id
  end

  test "duplicate_confirm shows reuse legend when profile resolutions include reuse" do
    user = users(:three)
    sign_in_as user
    stray = profiles(:stray)
    user.profiles.create!(name: "Stray Copy", copied_from: stray, labels: [ "blue" ])

    group = groups(:echo_shard)
    post duplicate_scan_our_group_path(group), params: { labels_text: "blue" }
    # Resolve stray profile as reuse
    post duplicate_resolve_our_group_path(group), params: { resolution: "reuse" }
    follow_redirect!
    assert_response :success

    assert_match "existing copy", response.body
    assert_match "will be linked into the new tree", response.body
  end

  private

  def sign_in_as(user)
    post session_path, params: {
      login: user.email_address,
      password: "Plur4l!Pr0files#2026"
    }
  end
end
