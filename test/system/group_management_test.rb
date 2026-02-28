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

  test "update relationship type from all to none" do
    everyone = groups(:everyone)
    link = group_groups(:friends_in_everyone)
    # Ensure child group has a sub-group
    child_group = link.child_group
    sub_group = Group.create!(name: "Subgroup", description: "A sub-group", user: @user)
    GroupGroup.create!(parent_group: child_group, child_group: sub_group)
    # Determine an example sub-group checkbox id
    visit manage_groups_our_group_path(everyone)

    # Starts as all — checkboxes for immediate sub-groups should be checked
    assert_text "Include sub-groups"
    sub = child_group.child_groups.order(:name).first
    checkbox_id = "included_#{link.id}_#{sub.id}"
    assert find("##{checkbox_id}", visible: :all).checked?

    # Switch to 'none' mode via radio and submit
    find("#inclusion_#{link.id}_none").click
    click_button "Save"
    assert_text "Relationship updated."

    # Page has reloaded — checkbox should now be unchecked
    assert_not find("##{checkbox_id}", visible: :all).checked?
    assert link.reload.none?
  end

  test "toggle relationship type from none to all" do
    everyone = groups(:everyone)
    link = group_groups(:friends_in_everyone)
    link.update!(inclusion_mode: "none")
    # Ensure child group has a sub-group
    child_group = link.child_group
    sub_group = Group.create!(name: "Subgroup", description: "A sub-group", user: @user)
    GroupGroup.create!(parent_group: child_group, child_group: sub_group)
    visit manage_groups_our_group_path(everyone)

    # Starts as none — immediate sub-group checkboxes should be unchecked
    child_group = link.child_group
    sub = child_group.child_groups.order(:name).first
    checkbox_id = "included_#{link.id}_#{sub.id}"
    assert_not find("##{checkbox_id}", visible: :all).checked?

    # Switch to 'all' mode via radio and submit
    find("#inclusion_#{link.id}_all").click
    click_button "Save"
    assert_text "Relationship updated."

    # Page has reloaded — checkbox should now be checked
    assert find("##{checkbox_id}", visible: :all).checked?
    assert link.reload.all?
  end

  test "checkbox does not appear if child group has no sub-groups" do
    everyone = groups(:everyone)
    link = group_groups(:friends_in_everyone)
    child_group = link.child_group
    # Ensure child group has no sub-groups
    child_group.child_links.destroy_all
    checkbox_id = "toggle_#{link.id}"

    visit manage_groups_our_group_path(everyone)

    # Toggle should not be present
    assert_no_text "Include sub-groups"
    assert_raises(Capybara::ElementNotFound) do
      find("##{checkbox_id}", visible: :all)
    end
  end

  test "public page shows all sub-group's profiles but hides none sub-group's profiles" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)

    # Build a deeper structure: everyone → friends → inner
    inner = user.groups.create!(name: "Inner Circle")
    GroupGroup.create!(parent_group: friends, child_group: inner)
    inner.profiles << profiles(:bob)

    # --- all: inner group and Bob should be visible ---
    visit group_path(everyone.uuid)

    within(".explorer__sidebar") do
      assert_text "Everyone"
      assert_text "Friends"
      assert_text "Inner Circle"
      assert_text "Bob"
      assert_text "Alice"
    end

    # --- Switch to none: inner group and Bob should disappear ---
    link = GroupGroup.find_by(parent_group: everyone, child_group: friends)
    link.update!(inclusion_mode: "none")

    visit group_path(everyone.uuid)

    within(".explorer__sidebar") do
      assert_text "Everyone"
      assert_text "Friends"
      assert_no_text "Inner Circle"
      assert_no_text "Bob"
      # Alice is directly in friends, so she still appears
      assert_text "Alice"
    end

    # --- Visiting friends directly still shows everything ---
    visit group_path(friends.uuid)

    within(".explorer__sidebar") do
      assert_text "Friends"
      assert_text "Inner Circle"
      assert_text "Bob"
      assert_text "Alice"
    end
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
