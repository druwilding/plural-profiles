require "application_system_test_case"

class ManageProfilesTest < ApplicationSystemTestCase
  setup do
    @user = users(:three)
    sign_in_via_browser
  end

  # -- Empty state (no profiles available, no existing group members) --

  test "does not show empty state when profiles are available to add" do
    # alpha_clan has some profiles and user :three has more unassigned ones
    visit manage_profiles_our_group_path(groups(:alpha_clan))

    assert_no_text "There are no profiles available to add here right now."
    assert_selector ".profile-grid"
  end

  test "does not show empty state when the group already has profiles" do
    visit manage_profiles_our_group_path(groups(:alpha_clan))

    # grove is a member of alpha_clan — .profile-grid should be present
    assert_selector ".profile-grid"
    assert_no_text "There are no profiles available to add here right now."
  end
end

# Separate class so setup signs in as a profileless account (user :four / solo_group).
class ManageProfilesEmptyStateTest < ApplicationSystemTestCase
  setup do
    @user = users(:four)
    sign_in_via_browser
  end

  test "shows empty state message when account has no profiles" do
    visit manage_profiles_our_group_path(groups(:solo_group))

    assert_text "There are no profiles available to add here right now."
    assert_text "You can"
    assert_text "first, then come back to add it to this group."
    assert_no_selector ".profile-grid"
  end

  test "create a profile link in empty state navigates to new profile page" do
    visit manage_profiles_our_group_path(groups(:solo_group))

    click_link "create a profile"

    assert_current_path new_our_profile_path
  end
end
