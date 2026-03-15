require "test_helper"

class GroupTest < ActiveSupport::TestCase
  test "requires name" do
    group = Group.new(user: users(:one))
    assert_not group.valid?
    assert_includes group.errors[:name], "can't be blank"
  end

  test "generates uuid on create" do
    group = users(:one).groups.create!(name: "New Group")
    assert_not_nil group.uuid
    assert_match(/\A[0-9a-f-]{36}\z/, group.uuid)
  end

  test "uuid must be unique" do
    existing = groups(:friends)
    group = Group.new(user: users(:two), name: "Dupe", uuid: existing.uuid)
    assert_not group.valid?
    assert_includes group.errors[:uuid], "has already been taken"
  end

  test "to_param returns uuid" do
    group = groups(:friends)
    assert_equal group.uuid, group.to_param
  end

  test "belongs to user" do
    assert_equal users(:one), groups(:friends).user
  end

  test "has many profiles through group_profiles" do
    friends = groups(:friends)
    assert_includes friends.profiles, profiles(:alice)
  end

  test "has many child groups" do
    everyone = groups(:everyone)
    assert_includes everyone.child_groups, groups(:friends)
  end

  test "has many parent groups" do
    friends = groups(:friends)
    assert_includes friends.parent_groups, groups(:everyone)
  end

  # -- descendant_group_ids / reachable_group_ids ---

  test "descendant_group_ids includes self" do
    everyone = groups(:everyone)
    ids = everyone.descendant_group_ids
    assert_includes ids, everyone.id
  end

  test "descendant_group_ids includes direct children" do
    everyone = groups(:everyone)
    ids = everyone.descendant_group_ids
    assert_includes ids, groups(:friends).id
  end

  test "descendant_group_ids includes nested children" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)
    inner = user.groups.create!(name: "Inner")
    GroupGroup.create!(parent_group: friends, child_group: inner)

    ids = everyone.descendant_group_ids
    assert_includes ids, inner.id
  end

  test "descendant_group_ids does not include unrelated groups" do
    everyone = groups(:everyone)
    ids = everyone.descendant_group_ids
    assert_not_includes ids, groups(:family).id
  end

  test "descendant_group_ids returns only self for leaf group" do
    friends = groups(:friends)
    ids = friends.descendant_group_ids
    assert_equal [ friends.id ], ids
  end

  # -- ancestor_group_ids ---

  test "ancestor_group_ids includes self" do
    friends = groups(:friends)
    ids = friends.ancestor_group_ids
    assert_includes ids, friends.id
  end

  test "ancestor_group_ids includes parents" do
    friends = groups(:friends)
    ids = friends.ancestor_group_ids
    assert_includes ids, groups(:everyone).id
  end

  # -- all_child_groups ---

  test "all_child_groups excludes self" do
    everyone = groups(:everyone)
    assert_not_includes everyone.all_child_groups, everyone
  end

  test "all_child_groups includes children" do
    everyone = groups(:everyone)
    assert_includes everyone.all_child_groups, groups(:friends)
  end

  # -- all_profiles ---

  test "all_profiles includes direct profiles" do
    friends = groups(:friends)
    assert_includes friends.all_profiles, profiles(:alice)
  end

  test "all_profiles includes profiles from child groups" do
    user = users(:one)
    everyone = groups(:everyone)
    # Alice is in friends, which is a child of everyone
    assert_includes everyone.all_profiles, profiles(:alice)
  end

  test "all_profiles respects inclusion overrides on groups" do
    # Alpha Clan has an override hiding Rogue Pack at [spectrum, prism_circle].
    # Profiles in Rogue Pack should still be visible via the Echo Shard path.
    alpha = groups(:alpha_clan)
    stray = profiles(:stray)

    # Stray is in both prism_circle and rogue_pack.
    # Via echo_shard → prism_circle, Stray is visible.
    assert_includes alpha.all_profiles, stray
  end

  test "all_profiles excludes profiles hidden by overrides" do
    # Castle Clan hides Drift and Ripple at path [flux]
    castle = groups(:castle_clan)
    drift = profiles(:drift)
    ripple = profiles(:ripple)

    assert_not_includes castle.all_profiles, drift
    assert_not_includes castle.all_profiles, ripple
  end

  test "all_profiles excludes cascade-hidden profiles" do
    # Castle Clan hides Static Burst at path [flux],
    # so Spark (in Static Burst) is cascade-hidden.
    castle = groups(:castle_clan)
    spark = profiles(:spark)

    assert_not_includes castle.all_profiles, spark
  end

  test "all_profiles includes non-hidden profiles in same parent" do
    # Castle Clan hides Drift/Ripple in Flux but Echo Shard's Mirage should be visible
    castle = groups(:castle_clan)
    mirage = profiles(:mirage)
    shadow = profiles(:shadow)

    assert_includes castle.all_profiles, mirage
    assert_includes castle.all_profiles, shadow
  end

  # -- visible_root_profiles ---

  test "visible_root_profiles returns direct profiles" do
    friends = groups(:friends)
    assert_includes friends.visible_root_profiles, profiles(:alice)
  end

  test "visible_root_profiles excludes profiles hidden at root path" do
    friends = groups(:friends)
    alice = profiles(:alice)

    InclusionOverride.create!(
      group: friends, path: [], target_type: "Profile", target_id: alice.id
    )

    assert_not_includes friends.visible_root_profiles, alice
  end

  # -- descendant_tree ---

  test "descendant_tree returns empty array for leaf group" do
    friends = groups(:friends)
    tree = friends.descendant_tree
    assert_equal [], tree
  end

  test "descendant_tree includes child groups" do
    everyone = groups(:everyone)
    tree = everyone.descendant_tree
    assert_equal 1, tree.length
    assert_equal groups(:friends), tree.first[:group]
  end

  test "descendant_tree includes profiles" do
    everyone = groups(:everyone)
    tree = everyone.descendant_tree
    friends_node = tree.find { |n| n[:group] == groups(:friends) }
    profile_names = friends_node[:profiles].map { |p| p[:profile].name }
    assert_includes profile_names, "Alice"
  end

  test "descendant_tree marks repeated profiles" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)
    inner = user.groups.create!(name: "Inner")
    GroupGroup.create!(parent_group: friends, child_group: inner)
    inner.profiles << profiles(:alice)

    tree = everyone.descendant_tree
    friends_node = tree.find { |n| n[:group] == friends }
    inner_node = friends_node[:children].find { |n| n[:group] == inner }

    # Alice appears first in friends (not repeated), then in inner (repeated)
    friends_alice = friends_node[:profiles].find { |p| p[:profile] == profiles(:alice) }
    inner_alice = inner_node[:profiles].find { |p| p[:profile] == profiles(:alice) }
    assert_not friends_alice[:repeated]
    assert inner_alice[:repeated]
  end

  test "descendant_tree respects group overrides" do
    # Alpha Clan hides Rogue Pack at [spectrum, prism_circle] path
    alpha = groups(:alpha_clan)
    tree = alpha.descendant_tree

    spectrum_node = tree.find { |n| n[:group] == groups(:spectrum) }
    prism_in_spectrum = spectrum_node[:children].find { |n| n[:group] == groups(:prism_circle) }
    # Rogue Pack should NOT appear under Spectrum → Prism Circle
    rogue_in_spectrum = prism_in_spectrum[:children].find { |n| n[:group] == groups(:rogue_pack) }
    assert_nil rogue_in_spectrum

    # But Rogue Pack SHOULD appear under Echo Shard → Prism Circle (diamond path)
    echo_node = tree.find { |n| n[:group] == groups(:echo_shard) }
    prism_in_echo = echo_node[:children].find { |n| n[:group] == groups(:prism_circle) }
    rogue_in_echo = prism_in_echo[:children].find { |n| n[:group] == groups(:rogue_pack) }
    assert_not_nil rogue_in_echo
  end

  test "descendant_tree respects profile overrides" do
    # Castle Clan hides Drift and Ripple at [flux]
    castle = groups(:castle_clan)
    tree = castle.descendant_tree

    flux_node = tree.find { |n| n[:group] == groups(:flux) }
    flux_profile_names = flux_node[:profiles].map { |p| p[:profile].name }
    assert_not_includes flux_profile_names, "Drift"
    assert_not_includes flux_profile_names, "Ripple"
  end

  test "descendant_tree hides groups with group overrides (cascade)" do
    # Castle Clan hides Static Burst at [flux] — it shouldn't appear at all
    castle = groups(:castle_clan)
    tree = castle.descendant_tree

    flux_node = tree.find { |n| n[:group] == groups(:flux) }
    static_child = flux_node[:children].find { |n| n[:group] == groups(:static_burst) }
    assert_nil static_child
  end

  # -- descendant_sections ---

  test "descendant_sections returns flat list of descendant groups" do
    everyone = groups(:everyone)
    sections = everyone.descendant_sections
    assert_equal [ groups(:friends) ], sections
  end

  test "descendant_sections excludes hidden groups" do
    # Castle Clan hides Static Burst at [flux]
    castle = groups(:castle_clan)
    sections = castle.descendant_sections
    section_groups = sections.select { |s| s.is_a?(Group) ? s : s }
    assert_not_includes section_groups, groups(:static_burst)
  end

  test "descendant_sections includes non-hidden groups" do
    castle = groups(:castle_clan)
    sections = castle.descendant_sections
    assert_includes sections, groups(:flux)
    assert_includes sections, groups(:echo_shard)
  end

  # -- management_tree ---

  test "management_tree returns empty array for leaf group" do
    friends = groups(:friends)
    tree = friends.management_tree
    assert_equal [], tree
  end

  test "management_tree includes ALL groups regardless of overrides" do
    # Castle Clan hides Static Burst, but management_tree should still include it
    castle = groups(:castle_clan)
    tree = castle.management_tree

    flux_node = tree.find { |n| n[:group] == groups(:flux) }
    static_node = flux_node[:children].find { |n| n[:group] == groups(:static_burst) }
    assert_not_nil static_node, "Static Burst should appear in management tree even when hidden"
  end

  test "management_tree marks hidden groups" do
    # Castle Clan hides Static Burst at [flux]
    castle = groups(:castle_clan)
    tree = castle.management_tree

    flux_node = tree.find { |n| n[:group] == groups(:flux) }
    static_node = flux_node[:children].find { |n| n[:group] == groups(:static_burst) }
    assert static_node[:hidden], "Static Burst should be marked as hidden"
    assert_not flux_node[:hidden], "Flux should NOT be marked as hidden"
  end

  test "management_tree marks cascade-hidden groups" do
    # If a group's ancestor is hidden, it should be cascade_hidden.
    # Alpha Clan hides Rogue Pack at [spectrum, prism_circle].
    # Add a child under Rogue Pack to test cascade_hidden.
    alpha = groups(:alpha_clan)
    tree = alpha.management_tree

    spectrum_node = tree.find { |n| n[:group] == groups(:spectrum) }
    prism_node = spectrum_node[:children].find { |n| n[:group] == groups(:prism_circle) }
    rogue_node = prism_node[:children].find { |n| n[:group] == groups(:rogue_pack) }

    assert rogue_node[:hidden], "Rogue Pack should be hidden (direct override)"
    assert_not rogue_node[:cascade_hidden], "Rogue Pack is not cascade-hidden (it's directly hidden)"
  end

  test "management_tree tracks path data" do
    alpha = groups(:alpha_clan)
    tree = alpha.management_tree

    spectrum_node = tree.find { |n| n[:group] == groups(:spectrum) }
    assert_equal [], spectrum_node[:path], "Spectrum's path should be empty (direct child of root)"
    assert_equal [ groups(:spectrum).id ], spectrum_node[:container_path]

    prism_node = spectrum_node[:children].find { |n| n[:group] == groups(:prism_circle) }
    assert_equal [ groups(:spectrum).id ], prism_node[:path]
    assert_equal [ groups(:spectrum).id, groups(:prism_circle).id ], prism_node[:container_path]
  end

  test "management_tree marks hidden profiles" do
    # Castle Clan hides Drift at [flux]
    castle = groups(:castle_clan)
    tree = castle.management_tree

    flux_node = tree.find { |n| n[:group] == groups(:flux) }
    drift_entry = flux_node[:profiles].find { |p| p[:profile] == profiles(:drift) }
    ripple_entry = flux_node[:profiles].find { |p| p[:profile] == profiles(:ripple) }

    assert drift_entry[:hidden], "Drift should be marked as hidden"
    assert ripple_entry[:hidden], "Ripple should be marked as hidden"
  end

  test "management_tree marks cascade-hidden profiles" do
    # Castle Clan hides Static Burst at [flux] — Spark is cascade-hidden
    castle = groups(:castle_clan)
    tree = castle.management_tree

    flux_node = tree.find { |n| n[:group] == groups(:flux) }
    static_node = flux_node[:children].find { |n| n[:group] == groups(:static_burst) }
    spark_entry = static_node[:profiles].find { |p| p[:profile] == profiles(:spark) }

    assert spark_entry[:cascade_hidden], "Spark should be cascade-hidden"
  end

  # -- management_root_profiles ---

  test "management_root_profiles returns direct profiles with flags" do
    alpha = groups(:alpha_clan)
    root_profiles = alpha.management_root_profiles

    grove_entry = root_profiles.find { |p| p[:profile] == profiles(:grove) }
    assert_not_nil grove_entry
    assert_not grove_entry[:hidden]
    assert_not grove_entry[:cascade_hidden]
    assert_equal [], grove_entry[:container_path]
  end

  test "management_root_profiles marks hidden root profiles" do
    friends = groups(:friends)
    alice = profiles(:alice)

    InclusionOverride.create!(
      group: friends, path: [], target_type: "Profile", target_id: alice.id
    )

    root_profiles = friends.management_root_profiles
    alice_entry = root_profiles.find { |p| p[:profile] == alice }
    assert alice_entry[:hidden]
  end

  # -- overrides_index ---

  test "overrides_index returns set of path-type-id tuples" do
    alpha = groups(:alpha_clan)
    index = alpha.send(:overrides_index)

    spectrum_id = groups(:spectrum).id
    prism_id = groups(:prism_circle).id
    rogue_id = groups(:rogue_pack).id

    assert index.include?([ [ spectrum_id, prism_id ], "Group", rogue_id ]),
           "Should include Rogue Pack override at [spectrum, prism_circle]"
  end

  test "overrides_index is empty for group with no overrides" do
    friends = groups(:friends)
    index = friends.send(:overrides_index)
    assert_empty index
  end

  # -- stale overrides are harmless ---

  test "stale override does not break tree traversal" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)

    # Create an override for a group that doesn't exist in the tree
    phantom_id = 999_999
    InclusionOverride.create!(
      group: everyone,
      path: [ friends.id ],
      target_type: "Group",
      target_id: phantom_id
    )

    # Tree methods should still work
    assert_nothing_raised { everyone.descendant_tree }
    assert_nothing_raised { everyone.descendant_sections }
    assert_nothing_raised { everyone.all_profiles }
  end

  # -- diamond path visibility ---

  test "diamond path: item visible via one path still accessible when hidden via another" do
    alpha = groups(:alpha_clan)
    rogue = groups(:rogue_pack)

    # Rogue Pack is hidden via [spectrum, prism_circle] but visible via [echo_shard, prism_circle]
    # It should appear in all_profiles and descendant_tree via the echo_shard path
    tree = alpha.descendant_tree

    echo_node = tree.find { |n| n[:group] == groups(:echo_shard) }
    prism_in_echo = echo_node[:children].find { |n| n[:group] == groups(:prism_circle) }
    rogue_in_echo = prism_in_echo[:children].find { |n| n[:group] == groups(:rogue_pack) }
    assert_not_nil rogue_in_echo, "Rogue Pack should be visible via Echo Shard path"

    stray = profiles(:stray)
    rogue_profiles = rogue_in_echo[:profiles].map { |p| p[:profile] }
    assert_includes rogue_profiles, stray
  end

  # -- created_at validation ---

  test "created_at cannot be in the future" do
    user = users(:one)
    group = user.groups.build(name: "Future Group", created_at: 1.hour.from_now)
    assert_not group.valid?
    assert_includes group.errors[:created_at], "can't be in the future"
  end

  test "created_at can be in the past" do
    user = users(:one)
    group = user.groups.build(name: "Past Group", created_at: 1.day.ago)
    assert group.valid?
  end

  # -- labels --

  test "labels defaults to empty array" do
    group = users(:one).groups.create!(name: "Labels Test")
    assert_equal [], group.labels
  end

  test "labels_text= parses comma-separated string into array" do
    group = groups(:friends)
    group.labels_text = "safe, work, close friends"
    assert_equal [ "safe", "work", "close friends" ], group.labels
  end

  test "labels_text= trims whitespace and rejects blanks" do
    group = groups(:friends)
    group.labels_text = "  safe ,, work ,  "
    assert_equal [ "safe", "work" ], group.labels
  end

  test "labels_text= deduplicates entries" do
    group = groups(:friends)
    group.labels_text = "safe, safe, work"
    assert_equal [ "safe", "work" ], group.labels
  end

  test "labels_text returns labels joined with comma and space" do
    group = groups(:friends)
    group.labels = [ "safe", "work" ]
    assert_equal "safe, work", group.labels_text
  end

  test "labels_text returns empty string when no labels" do
    group = groups(:friends)
    group.labels = []
    assert_equal "", group.labels_text
  end

  test "normalize_labels cleans up array on validation" do
    group = groups(:friends)
    group.labels = [ "  safe  ", "", "work" ]
    group.validate
    assert_equal [ "safe", "work" ], group.labels
  end

  test "labels round-trip through save" do
    group = users(:one).groups.create!(name: "Labels RT")
    group.update!(labels: [ "family", "private" ])
    assert_equal [ "family", "private" ], group.reload.labels
  end

  # -- Phase 1: group theme association --

  test "group without a theme is valid" do
    group = users(:one).groups.build(name: "Themeless")
    assert group.valid?
  end

  test "group with a theme is valid" do
    group = users(:one).groups.build(name: "Themed", theme: themes(:dark_forest))
    assert group.valid?
  end

  test "theme association is accessible via fixture" do
    assert_equal themes(:dark_forest), groups(:friends).theme
  end

  test "deleting a theme nullifies the group theme_id" do
    group = users(:one).groups.create!(name: "Will Lose Theme", theme: themes(:sunset))
    assert_not_nil group.theme_id
    themes(:sunset).destroy
    assert_nil group.reload.theme_id
  end
end
