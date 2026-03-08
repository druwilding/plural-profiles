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
    follow_redirect!
    assert_response :success
    assert_match "Friends", response.body
    assert_no_match "Edit", response.body
    assert_no_match "Delete", response.body
    assert_no_match "Manage profiles", response.body
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

  test "manage_groups shows empty state for group with no children or profiles" do
    sign_in_as @user
    empty_group = @user.groups.create!(name: "Empty")
    get manage_groups_our_group_path(empty_group)
    assert_response :success
    assert_match "no sub-groups or profiles yet", response.body
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

  private

  def sign_in_as(user)
    post session_path, params: {
      email_address: user.email_address,
      password: "Plur4l!Pr0files#2026"
    }
  end
end
