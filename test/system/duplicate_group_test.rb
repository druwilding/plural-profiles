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

    click_button "Confirm & duplicate"

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
    assert_text "Conflict 1"
    assert_text prism.name

    # Choose to create a new copy (only 1 conflict — Prism Circle; Rogue Pack has no copy)
    choose "Create a new copy"
    click_button "Next"

    assert_text "Confirm duplication"
    click_button "Confirm & duplicate"

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
    assert_text "Conflict 1"
    assert_text prism.name

    # Choose to reuse — should skip Rogue Pack conflict entirely
    choose "Use the existing copy"
    click_button "Next"

    # Should go straight to confirm (Rogue Pack conflict skipped)
    assert_text "Confirm duplication"
    click_button "Confirm & duplicate"

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
    click_link "Start over"

    assert_text "Duplicate group"
  end
end
