require "test_helper"

class Our::GroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @group = groups(:friends)
    @other_user = users(:two)
    @other_group = groups(:family)
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

  test "manage_groups shows available groups" do
    sign_in_as @user
    everyone = groups(:everyone)
    get manage_groups_our_group_path(everyone)
    assert_response :success
  end

  test "manage_groups excludes self and already-added groups" do
    sign_in_as @user
    everyone = groups(:everyone)
    get manage_groups_our_group_path(everyone)
    # User one only has friends + everyone, and friends is already a child,
    # everyone is self, so the available list should be empty
    assert_match "All your other groups are already in this group", response.body
  end

  test "manage_groups excludes ancestor groups to prevent cycles" do
    sign_in_as @user
    everyone = groups(:everyone)
    # everyone → friends already exists in fixtures
    coworkers = @user.groups.create!(name: "Coworkers")

    # From friends' perspective, everyone is an ancestor — must be excluded
    get manage_groups_our_group_path(@group)
    assert_response :success
    assert_no_match "everyone", response.body
    assert_match "Coworkers", response.body
  end

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

  test "manage_groups redirects logged-out user to sign in" do
    get manage_groups_our_group_path(@group)
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

  test "manage_groups redirects wrong user to public group" do
    sign_in_as @other_user
    get manage_groups_our_group_path(@group)
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
end
