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

  test "public page hides groups removed by inclusion override" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)

    # Build a deeper structure: everyone → friends → inner
    inner = user.groups.create!(name: "Inner Circle")
    GroupGroup.create!(parent_group: friends, child_group: inner)
    inner.profiles << profiles(:bob)

    # --- No overrides: inner group and Bob should be visible ---
    visit group_path(everyone.uuid)

    within(".explorer__sidebar") do
      assert_text "Everyone"
      assert_text "Friends"
      assert_text "Inner Circle"
      assert_text "Bob"
      assert_text "Alice"
    end

    # --- Add override to hide Inner Circle at path [friends.id] in everyone ---
    InclusionOverride.create!(
      group: everyone,
      path: [ friends.id ],
      target_type: "Group",
      target_id: inner.id
    )

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

  test "public page hides sub-groups via inclusion overrides" do
    user = users(:one)
    everyone = groups(:everyone)

    # Create a fresh friends branch with two immediate sub-groups
    friends = user.groups.create!(name: "Friends Selected", description: "Test friends")
    close = user.groups.create!(name: "Close Friends", description: "Close pals")
    acquaintances = user.groups.create!(name: "Acquaintances", description: "Not close")

    GroupGroup.create!(parent_group: friends, child_group: close)
    GroupGroup.create!(parent_group: friends, child_group: acquaintances)
    GroupGroup.create!(parent_group: everyone, child_group: friends)

    # Hide acquaintances at path [friends.id] in everyone
    InclusionOverride.create!(
      group: everyone,
      path: [ friends.id ],
      target_type: "Group",
      target_id: acquaintances.id
    )

    visit group_path(everyone.uuid)

    within(".explorer__sidebar") do
      assert_text "Everyone"
      assert_text "Friends Selected"
      assert_text "Close Friends"
      assert_no_text "Acquaintances"
    end
  end

  test "public page renders childless sub-group as tree leaf not folder" do
    user = users(:one)
    everyone = groups(:everyone)

    empty = user.groups.create!(name: "Empty Crew")
    GroupGroup.create!(parent_group: everyone, child_group: empty)

    visit group_path(everyone.uuid)

    within(".explorer__sidebar") do
      # The childless group should be a leaf node (li.tree__leaf > a > .tree__label)
      assert_selector "li.tree__leaf > a.tree__item > .tree__label", text: "Empty Crew"

      # It should NOT be a folder with a toggle arrow
      assert_no_selector "li.tree__folder > .tree__row .tree__label", text: "Empty Crew"
    end
  end

  test "public page renders group as leaf when all children are hidden" do
    user = users(:one)
    everyone = groups(:everyone)

    outer = user.groups.create!(name: "Outer Ring")
    inner = user.groups.create!(name: "Inner Ring")
    GroupGroup.create!(parent_group: outer, child_group: inner)
    # outer has a sub-group but no direct profiles — with its only child
    # hidden, it should render as a leaf in the parent tree
    GroupGroup.create!(parent_group: everyone, child_group: outer)

    InclusionOverride.create!(
      group: everyone,
      path: [ outer.id ],
      target_type: "Group",
      target_id: inner.id
    )

    visit group_path(everyone.uuid)

    within(".explorer__sidebar") do
      assert_selector "li.tree__leaf > a.tree__item > .tree__label", text: "Outer Ring"
      assert_no_selector "li.tree__folder > .tree__row .tree__label", text: "Outer Ring"
      # The hidden child should not appear at all
      assert_no_text "Inner Ring"
    end
  end

  test "public page renders group as leaf when all profiles are hidden" do
    user = users(:one)
    everyone = groups(:everyone)

    crew = user.groups.create!(name: "Quiet Crew")
    crew.profiles << profiles(:bob)
    # The group has a direct profile but no sub-groups — with its only
    # profile hidden, it should render as a leaf
    GroupGroup.create!(parent_group: everyone, child_group: crew)

    InclusionOverride.create!(
      group: everyone,
      path: [ crew.id ],
      target_type: "Profile",
      target_id: profiles(:bob).id
    )

    visit group_path(everyone.uuid)

    within(".explorer__sidebar") do
      assert_selector "li.tree__leaf > a.tree__item > .tree__label", text: "Quiet Crew"
      assert_no_selector "li.tree__folder > .tree__row .tree__label", text: "Quiet Crew"
      # Bob should not appear under Quiet Crew
      assert_no_selector "li.tree__leaf > a.tree__item > .tree__label", text: "Bob"
    end
  end

  test "public page marks repeated profiles in the tree" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)
    inner = user.groups.create!(name: "Inner Circle")
    GroupGroup.create!(parent_group: friends, child_group: inner)

    alice = profiles(:alice)
    # Alice is already in friends (fixture); add her to inner too
    inner.profiles << alice

    visit group_path(everyone.uuid)

    within(".explorer__sidebar") do
      # Alice should appear twice: once not repeated, once repeated
      labels = all(".tree__label", text: "Alice")
      assert_equal 2, labels.length, "Alice should appear twice in the tree"

      repeated_labels = all(".tree__label--repeated", text: "Alice")
      assert_equal 1, repeated_labels.length, "Exactly one Alice should be marked as repeated"
    end
  end

  test "content panel hides profiles excluded by inclusion overrides" do
    castle = groups(:castle_clan)
    flux = groups(:flux)

    visit group_path(castle.uuid)

    # The sidebar should show Flux and Echo Shard but NOT Drift/Ripple
    # (hidden by inclusion overrides on castle_clan)
    within(".explorer__sidebar") do
      assert_text "Flux"
      assert_text "Echo Shard"
      assert_no_text "Drift"
      assert_no_text "Ripple"
    end

    # Click Flux in the tree to load its content panel
    within(".explorer__sidebar") do
      find(".tree__item[data-group-uuid='#{flux.uuid}']").click
    end

    # The content panel should show Flux's name but NOT its hidden profiles
    within(".explorer__content") do
      assert_text "Flux"
      assert_no_text "Drift"
      assert_no_text "Ripple"
    end
  end

  test "alpha clan diamond path shows Rogue Pack via Echo Shard but not via Spectrum" do
    alpha = groups(:alpha_clan)
    spectrum = groups(:spectrum)

    # The inclusion override on alpha_clan hides Rogue Pack when reached
    # via Spectrum → Prism Circle, but the diamond path through Echo Shard
    # → Prism Circle has no override, so Rogue Pack appears there.
    visit group_path(alpha.uuid)

    within(".explorer__sidebar") do
      # All profiles visible (Grove direct, Ember + Stray in Prism Circle)
      assert_text "Grove"
      assert_text "Ember"
      assert_text "Stray"
      # Rogue Pack is visible via Echo Shard path
      assert_text "Rogue Pack"
    end

    # Visiting Spectrum directly shows everything (no overrides on its own view)
    visit group_path(spectrum.uuid)

    within(".explorer__sidebar") do
      assert_text "Ember"
      assert_text "Stray"
      assert_text "Rogue Pack"
    end
  end

  test "no-JS fallback profile links use root group context" do
    alpha = groups(:alpha_clan)
    ember = profiles(:ember)

    # Ember is in Prism Circle (a descendant of Alpha Clan via both Spectrum
    # and Echo Shard paths). The fallback profile link uses the root group UUID.
    visit group_profile_path(alpha.uuid, ember.uuid)

    assert_text "Ember"
    assert_text "Back to Alpha Clan"
  end

  test "no-JS fallback blocks profiles hidden by inclusion overrides" do
    castle = groups(:castle_clan)
    drift = profiles(:drift)

    # Drift is in Flux, but hidden from Castle Clan via an inclusion override.
    # Accessing Drift through Castle Clan should 404.
    visit group_profile_path(castle.uuid, drift.uuid)

    assert_text "RecordNotFound"
  end

  test "no-JS fallback blocks cascade-hidden profiles" do
    castle = groups(:castle_clan)
    spark = profiles(:spark)

    # Spark is in Static Burst, which is hidden from Castle Clan at path
    # [flux.id]. Since the group is hidden, its profiles are
    # cascade-hidden — Spark should not be accessible through Castle Clan.
    visit group_profile_path(castle.uuid, spark.uuid)

    assert_text "RecordNotFound"
  end
end
