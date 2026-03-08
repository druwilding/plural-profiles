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

  test "manage groups shows empty state when group has no sub-groups or profiles" do
    empty = @user.groups.create!(name: "Empty Group")
    visit manage_groups_our_group_path(empty)

    assert_text "no sub-groups or profiles yet"
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

    assert_text "Add a group to"

    within(".card-list") do
      card = find(".card", text: castle.name)
      within(card) { click_link "Add to #{alpha.name}" }
    end

    assert_current_path manage_groups_our_group_path(alpha)
    assert_text "Group added."
    assert_text "Castle Clan"
  end

  test "shows message when all groups are already in tree" do
    user = users(:one)
    sign_in_via_browser(user: user)

    visit manage_groups_our_group_path(groups(:everyone))

    assert_text "All your other groups are already in this tree."
  end

  # -- Removing a direct sub-group --

  test "remove a direct sub-group from manage groups" do
    alpha = groups(:alpha_clan)

    visit manage_groups_our_group_path(alpha)

    accept_confirm do
      click_link "Remove from Alpha Clan", match: :first
    end

    assert_current_path manage_groups_our_group_path(alpha)
    assert_text "Group removed."
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
        click_link "Remove from Alpha Clan"
      end
    end

    assert_text "Group removed."

    visit group_path(alpha.uuid)
    within(".explorer__sidebar") do
      assert_no_text "Spectrum"
    end
  end

  # -- Back link --

  test "back link returns to group show page" do
    alpha = groups(:alpha_clan)
    visit manage_groups_our_group_path(alpha)

    click_link "Back to group"

    assert_current_path our_group_path(alpha)
  end

  private

  def sign_in_via_browser(user: nil)
    user ||= @user
    visit new_session_path
    fill_in "Email address", with: user.email_address
    fill_in "Password", with: "Plur4l!Pr0files#2026"
    click_button "Sign in"
    assert_current_path root_path
  end
end
