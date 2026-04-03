require "application_system_test_case"

class ManageGroupsTest < ApplicationSystemTestCase
  setup do
    @user = users(:three)
    sign_in_via_browser
  end

  # -- Navigation & page rendering --

  test "navigate to manage groups from group show page" do
    visit our_group_path(groups(:alpha_clan))
    click_link "Manage groups"

    assert_current_path manage_groups_our_group_path(groups(:alpha_clan))
    assert_text "Manage groups in"
    assert_text "Alpha Clan"
  end

  test "manage groups shows full descendant tree including hidden items" do
    visit manage_groups_our_group_path(groups(:alpha_clan))

    assert_text "Spectrum"
    assert_text "Prism Circle"
    # Rogue Pack is hidden from public view via override, but still visible in editor tree
    assert_text "Rogue Pack"
  end

  test "manage groups marks hidden nodes with hidden tag" do
    visit manage_groups_our_group_path(groups(:alpha_clan))

    # Rogue Pack is hidden via override - it should appear in a node with tree-editor__node--hidden
    assert_selector ".tree-editor__node--hidden .tree-editor__name", text: "Rogue Pack"
  end

  test "manage groups shows profiles in the tree" do
    visit manage_groups_our_group_path(groups(:castle_clan))

    # Drift is a profile in Flux - should appear in the tree even though hidden
    assert_text "Drift"
    assert_text "Ripple"
    assert_text "Mirage"
  end

  test "manage groups shows castle clan hidden state correctly" do
    visit manage_groups_our_group_path(groups(:castle_clan))

    # Static Burst is hidden - should appear in node--hidden
    assert_selector ".tree-editor__node--hidden .tree-editor__name", text: "Static Burst"

    # Echo Shard should NOT be hidden
    assert_no_selector ".tree-editor__node--hidden .tree-editor__name", text: "Echo Shard"
  end

  # -- Adding a sub-group --

  test "add a sub-group from manage groups" do
    alpha = groups(:alpha_clan)
    castle = groups(:castle_clan)

    visit manage_groups_our_group_path(alpha)

    within(".profile-grid") do
      card = find(".card", text: castle.name)
      within(card) { click_link "Add to group" }
    end

    assert_current_path manage_groups_our_group_path(alpha)
    assert_text "Group added."
    assert_text "Castle Clan"
  end

  # -- Removing a direct sub-group --

  test "remove a direct sub-group from manage groups" do
    alpha = groups(:alpha_clan)

    visit manage_groups_our_group_path(alpha)

    accept_confirm do
      click_link "Remove from group", match: :first
    end

    assert_current_path manage_groups_our_group_path(alpha)
    assert_text "Group removed."
  end

  # -- Empty state (no groups available, no existing tree) --

  test "does not show empty state when groups are available to add" do
    visit manage_groups_our_group_path(groups(:alpha_clan))

    assert_no_text "There are no groups available to add here right now."
    assert_selector ".profile-grid"
  end

  test "does not show empty state when a tree exists" do
    visit manage_groups_our_group_path(groups(:alpha_clan))

    assert_selector ".tree-editor"
    assert_no_text "There are no groups available to add here right now."
  end

  # -- Verifying public effects --

  test "removing sub-group via manage groups removes it from public view" do
    alpha = groups(:alpha_clan)

    visit group_path(alpha.uuid)
    within(".explorer__sidebar") do
      assert_text "Spectrum"
    end

    sign_in_via_browser
    visit manage_groups_our_group_path(alpha)

    accept_confirm do
      within find(".tree-editor__item-info", text: "Spectrum") do
        click_link "Remove from group"
      end
    end

    assert_text "Group removed."

    visit group_path(alpha.uuid)
    within(".explorer__sidebar") do
      assert_no_text "Spectrum"
    end
  end
end

# Separate class so setup signs in as a single-group account (user :two / family).
class ManageGroupsEmptyStateTest < ApplicationSystemTestCase
  setup do
    @user = users(:two)
    sign_in_via_browser
  end

  test "shows empty state message when account has only one group" do
    visit manage_groups_our_group_path(groups(:family))

    assert_text "There are no groups available to add here right now."
    assert_text "You can"
    assert_text "first, then come back to add it to this group."
    assert_no_selector ".profile-grid"
  end

  test "create a group link in empty state navigates to new group page" do
    visit manage_groups_our_group_path(groups(:family))

    click_link "create a group"

    assert_current_path new_our_group_path
  end
end
