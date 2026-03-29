require "application_system_test_case"

class DuplicateGroupTest < ApplicationSystemTestCase
  setup do
    @user = users(:three)
    sign_in_via_browser
  end

  test "duplicate a group with no conflicts (straight to confirm)" do
    group = groups(:echo_shard)
    visit our_group_path(group)
    click_link "Duplicate"

    assert_text "Duplicate group"
    assert_text group.name

    fill_in "Labels for all copies", with: "blue"
    click_button "Next"

    # Should skip straight to confirm since no copies exist
    assert_text "Confirm duplication"
    assert_text group.name
    assert_text "blue"

    click_button "Confirm and duplicate"

    assert_text "Group duplicated"
  end

  test "duplicate a group with conflicts and resolve them" do
    prism = groups(:prism_circle)
    @user.groups.create!(name: "Prism Circle (blue)", copied_from: prism, labels: [ "blue" ])

    group = groups(:echo_shard)
    visit our_group_path(group)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "blue"
    click_button "Next"

    # Should show conflict resolution
    assert_text "Group question 1"
    assert_text prism.name

    # Choose to create a new copy (only 1 conflict — Prism Circle; Rogue Pack has no copy)
    choose "Create a new copy"
    click_button "Next"

    assert_text "Confirm duplication"
    click_button "Confirm and duplicate"

    assert_text "Group duplicated"
  end

  test "reuse existing copy skips descendant conflicts" do
    prism = groups(:prism_circle)
    rogue = groups(:rogue_pack)
    @user.groups.create!(name: "Prism Circle (blue)", copied_from: prism, labels: [ "blue" ])
    @user.groups.create!(name: "Rogue Pack (blue)", copied_from: rogue, labels: [ "blue" ])

    group = groups(:echo_shard)
    visit our_group_path(group)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "blue"
    click_button "Next"

    # Should show conflict for Prism Circle
    assert_text "Group question 1"
    assert_text prism.name

    # Choose to reuse — should skip Rogue Pack conflict entirely
    choose "Use the existing copy"
    click_button "Next"

    # Should go straight to confirm (Rogue Pack conflict skipped)
    assert_text "Confirm duplication"
    click_button "Confirm and duplicate"

    assert_text "Group duplicated"
  end

  test "empty labels shows error" do
    group = groups(:echo_shard)
    visit our_group_path(group)
    click_link "Duplicate"

    click_button "Next"

    assert_text "at least one label"
  end

  test "cancel returns to group show page" do
    group = groups(:echo_shard)
    visit our_group_path(group)
    click_link "Duplicate"

    click_link "Cancel"

    assert_current_path our_group_path(group)
  end

  test "start over from confirm returns to duplicate form" do
    group = groups(:echo_shard)
    visit our_group_path(group)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "restart_test"
    click_button "Next"

    assert_text "Confirm duplication"
    click_link "Cancel"

    assert_text "Duplicate group"
  end

  test "confirm page shows full tree with groups and profiles" do
    group = groups(:echo_shard)
    visit our_group_path(group)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "tree_test"
    click_button "Next"

    assert_text "Confirm duplication"
    # Root group name in tree
    assert_text group.name
    # Child groups
    assert_text groups(:prism_circle).name
    assert_text groups(:rogue_pack).name
    # Profiles
    assert_text profiles(:mirage).name
    assert_text profiles(:ember).name
    assert_text profiles(:stray).name
  end

  test "confirm page shows labels on tree items" do
    group = groups(:echo_shard)
    visit our_group_path(group)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "labelled"
    click_button "Next"

    assert_text "Confirm duplication"
    # The label should appear on the page (multiple times — root + tree items)
    assert_selector ".label-badge", text: "labelled", minimum: 2
  end

  test "confirm page does not show reuse legend when no conflicts exist" do
    group = groups(:echo_shard)
    visit our_group_path(group)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "no_reuse"
    click_button "Next"

    assert_text "Confirm duplication"
    assert_no_text "existing copy"
    assert_no_text "will be linked into the new tree"
  end

  test "confirm page shows existing copy tag and legend for reused groups" do
    prism = groups(:prism_circle)
    @user.groups.create!(name: "Prism Copy", copied_from: prism, labels: [ "reuse_tag" ])

    group = groups(:echo_shard)
    visit our_group_path(group)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "reuse_tag"
    click_button "Next"

    # Should show conflict — choose reuse
    assert_text "Group question 1"
    choose "Use the existing copy"
    click_button "Next"

    assert_text "Confirm duplication"
    # Legend should be visible
    assert_text "will be linked into the new tree"
    # The reused group should show "existing copy" tag
    assert_selector ".tree-editor__tag--reuse", text: "existing copy"
  end

  test "confirm page shows hidden tag for items with inclusion overrides" do
    # Castle Clan has overrides that hide static_burst, drift, and ripple
    group = groups(:castle_clan)
    visit our_group_path(group)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "hidden_test"
    click_button "Next"

    assert_text "Confirm duplication"
    # Should show "hidden" tags for the overridden items
    assert_selector ".tree-editor__tag--hidden", text: "hidden", minimum: 1
  end

  test "confirm page renders collapsible tree structure" do
    group = groups(:echo_shard)
    visit our_group_path(group)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "tree_ui"
    click_button "Next"

    assert_text "Confirm duplication"
    # Tree structure should be present
    assert_selector ".tree-editor"
    assert_selector ".tree-editor__folder--root"
    assert_selector "details[open]", minimum: 1
  end

  test "confirm page shows multiple labels when provided" do
    group = groups(:echo_shard)
    visit our_group_path(group)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "first, second"
    click_button "Next"

    assert_text "Confirm duplication"
    assert_selector ".label-badge", text: "first"
    assert_selector ".label-badge", text: "second"
  end

  test "multi-label duplicate then higher-level duplicate triggers conflict resolution" do
    # Step 1: Duplicate Prism Circle with "black, white" — no conflicts, straight to confirm.
    prism = groups(:prism_circle)
    visit our_group_path(prism)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "black, white"
    click_button "Next"

    assert_text "Confirm duplication"
    click_button "Confirm and duplicate"
    assert_text "Group duplicated"

    # Step 2: Duplicate Echo Shard (which contains Prism Circle) with the same labels.
    # Because a copy of Prism Circle with BOTH "black" and "white" now exists,
    # we should hit the conflict resolution screen — not jump straight to confirm.
    echo = groups(:echo_shard)
    visit our_group_path(echo)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "black, white"
    click_button "Next"

    assert_text "Group question 1"
    assert_text prism.name

    # Resolve by reusing the existing copy — should skip Rogue Pack conflict too
    choose "Use the existing copy"
    click_button "Next"

    assert_text "Confirm duplication"
    assert_selector ".label-badge", text: "black"
    assert_selector ".label-badge", text: "white"

    click_button "Confirm and duplicate"
    assert_text "Group duplicated"
  end

  test "reversed label order still triggers conflict resolution" do
    # Duplicate Prism Circle with "black, white"
    prism = groups(:prism_circle)
    visit our_group_path(prism)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "black, white"
    click_button "Next"

    assert_text "Confirm duplication"
    click_button "Confirm and duplicate"
    assert_text "Group duplicated"

    # Now duplicate Echo Shard with labels in reversed order: "white, black"
    echo = groups(:echo_shard)
    visit our_group_path(echo)
    click_link "Duplicate"

    fill_in "Labels for all copies", with: "white, black"
    click_button "Next"

    # Should still detect the conflict despite reversed input order
    assert_text "Group question 1"
    assert_text prism.name

    choose "Create a new copy"
    click_button "Next"

    # Rogue Pack also has a copy (created as child of Prism Circle's copy)
    assert_text "Group question 2"
    assert_text groups(:rogue_pack).name

    choose "Create a new copy"
    click_button "Next"

    # Profile conflicts — Ember and Stray were also copied in step 1
    assert_text "Profile question 1"
    choose "Create a new copy"
    click_button "Next"

    assert_text "Profile question 2"
    choose "Create a new copy"
    click_button "Next"

    assert_text "Confirm duplication"
    click_button "Confirm and duplicate"
    assert_text "Group duplicated"
  end
end
