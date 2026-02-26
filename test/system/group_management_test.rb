require "application_system_test_case"

class GroupManagementTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_via_browser
  end

  test "create a new group" do
    within(".site-header") { click_link "New group" }
    fill_in "Name", with: "Colleagues"
    fill_in "Description", with: "People we work with."
    click_button "Create group"

    assert_text "Group created."
    assert_text "Colleagues"
  end

  test "edit an existing group" do
    visit our_group_path(groups(:friends))
    click_link "Edit"
    assert_current_path edit_our_group_path(groups(:friends))
    fill_in "Name", with: "Best Friends"
    click_button "Update group"

    assert_text "Group updated."
    assert_text "Best Friends"
  end

  test "delete a group" do
    visit our_group_path(groups(:friends))
    accept_confirm do
      click_link "Delete"
    end

    assert_text "Group deleted."
  end

  test "manage profiles in group" do
    visit our_group_path(groups(:friends))
    click_link "Manage profiles"

    assert_text "Manage profiles in"
    assert_text "Alice" # already in the group
    assert_text "Bob"   # available to add
  end

  test "toggle relationship type from nested to overlapping" do
    everyone = groups(:everyone)
    link = group_groups(:friends_in_everyone)
    checkbox_id = "toggle_#{link.id}"

    visit manage_groups_our_group_path(everyone)

    # Starts as nested — checkbox should be checked
    assert_text "Include sub-groups"
    assert find("##{checkbox_id}", visible: :all).checked?

    # Click the toggle to switch to overlapping
    find(".toggle-label").click
    assert_text "Relationship updated."

    # Page has reloaded — checkbox should now be unchecked
    assert_not find("##{checkbox_id}", visible: :all).checked?
    assert link.reload.overlapping?
  end

  test "toggle relationship type from overlapping to nested" do
    everyone = groups(:everyone)
    link = group_groups(:friends_in_everyone)
    link.update!(relationship_type: "overlapping")
    checkbox_id = "toggle_#{link.id}"

    visit manage_groups_our_group_path(everyone)

    # Starts as overlapping — checkbox should be unchecked
    assert_not find("##{checkbox_id}", visible: :all).checked?

    # Click the toggle to switch to nested
    find(".toggle-label").click
    assert_text "Relationship updated."

    # Page has reloaded — checkbox should now be checked
    assert find("##{checkbox_id}", visible: :all).checked?
    assert link.reload.nested?
  end

  private

  def sign_in_via_browser
    visit new_session_path
    fill_in "Email address", with: @user.email_address
    fill_in "Password", with: "Plur4l!Pr0files#2026"
    click_button "Sign in"
    assert_current_path root_path
  end
end
