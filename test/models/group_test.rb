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

  # -- Copy lineage (Phase 5) --

  test "copied_from association" do
    original = users(:one).groups.create!(name: "Original")
    copy = users(:one).groups.create!(name: "Copy", copied_from: original)
    assert_equal original, copy.copied_from
  end

  test "copies association" do
    original = users(:one).groups.create!(name: "Original")
    copy1 = users(:one).groups.create!(name: "Copy 1", copied_from: original)
    copy2 = users(:one).groups.create!(name: "Copy 2", copied_from: original)
    assert_includes original.copies, copy1
    assert_includes original.copies, copy2
  end

  test "copies_with_labels returns copies that have ALL given labels" do
    original = users(:one).groups.create!(name: "Original")
    matching = users(:one).groups.create!(name: "Matching", copied_from: original, labels: [ "blue", "safe" ])
    partial  = users(:one).groups.create!(name: "Partial",  copied_from: original, labels: [ "blue" ])
    other    = users(:one).groups.create!(name: "Other",    copied_from: original, labels: [ "red" ])

    result = original.copies_with_labels([ "blue", "safe" ])
    assert_includes result, matching
    assert_not_includes result, partial
    assert_not_includes result, other
  end

  test "copies_with_labels returns empty when no copies match" do
    original = users(:one).groups.create!(name: "Original")
    users(:one).groups.create!(name: "Copy", copied_from: original, labels: [ "red" ])
    assert_empty original.copies_with_labels([ "blue" ])
  end

  test "copies_with_labels finds transitive copies (copy of a copy)" do
    original = users(:one).groups.create!(name: "Original")
    copy_purple = users(:one).groups.create!(name: "Copy (purple)", copied_from: original, labels: [ "purple" ])
    copy_yellow = users(:one).groups.create!(name: "Copy (yellow)", copied_from: copy_purple, labels: [ "yellow" ])

    result = original.copies_with_labels([ "yellow" ])
    assert_includes result, copy_yellow
    assert_not_includes result, copy_purple
  end

  test "copies_with_labels finds deeply nested transitive copies" do
    original = users(:one).groups.create!(name: "Original")
    gen1 = users(:one).groups.create!(name: "Gen 1", copied_from: original, labels: [ "a" ])
    gen2 = users(:one).groups.create!(name: "Gen 2", copied_from: gen1, labels: [ "b" ])
    gen3 = users(:one).groups.create!(name: "Gen 3", copied_from: gen2, labels: [ "c" ])

    result = original.copies_with_labels([ "c" ])
    assert_includes result, gen3
    assert_equal 1, result.count
  end

  test "deleting the original nullifies copied_from_id on copies" do
    original = users(:one).groups.create!(name: "Original")
    copy = users(:one).groups.create!(name: "Copy", copied_from: original)
    original.destroy
    assert_nil copy.reload.copied_from_id
  end

  # -- scan_for_conflicts (Phase 6) --

  test "scan_for_conflicts returns empty when no copies exist" do
    alpha = groups(:alpha_clan)
    conflicts = alpha.scan_for_conflicts([ "blue" ])
    assert_empty conflicts
  end

  test "scan_for_conflicts returns conflicts for sub-groups with matching labeled copies" do
    user = users(:three)
    prism = groups(:prism_circle)
    rogue = groups(:rogue_pack)

    # Create copies with the "blue" label
    user.groups.create!(name: "Prism Circle (blue)", copied_from: prism, labels: [ "blue" ])
    user.groups.create!(name: "Rogue Pack (blue)", copied_from: rogue, labels: [ "blue" ])

    echo = groups(:echo_shard)
    conflicts = echo.scan_for_conflicts([ "blue" ])

    assert_equal 2, conflicts.length
    original_ids = conflicts.map { |c| c[:original_id] }
    assert_includes original_ids, prism.id
    assert_includes original_ids, rogue.id
  end

  test "scan_for_conflicts returns conflicts in depth-first order" do
    user = users(:three)
    prism = groups(:prism_circle)
    rogue = groups(:rogue_pack)

    user.groups.create!(name: "Prism Copy", copied_from: prism, labels: [ "blue" ])
    user.groups.create!(name: "Rogue Copy", copied_from: rogue, labels: [ "blue" ])

    spectrum = groups(:spectrum)
    conflicts = spectrum.scan_for_conflicts([ "blue" ])

    # Prism Circle should come before Rogue Pack (depth-first)
    prism_index = conflicts.index { |c| c[:original_id] == prism.id }
    rogue_index = conflicts.index { |c| c[:original_id] == rogue.id }
    assert prism_index < rogue_index, "Prism Circle should appear before Rogue Pack in depth-first order"
  end

  test "scan_for_conflicts does not flag sub-groups without matching copies" do
    user = users(:three)
    prism = groups(:prism_circle)

    # Create a copy with a different label
    user.groups.create!(name: "Prism Circle (red)", copied_from: prism, labels: [ "red" ])

    echo = groups(:echo_shard)
    conflicts = echo.scan_for_conflicts([ "blue" ])
    # Only group conflicts — no profile conflicts either
    group_conflicts = conflicts.select { |c| c[:original_type] == "Group" }
    assert_empty group_conflicts
  end

  # -- scan_for_conflicts: profile conflicts --

  test "scan_for_conflicts returns profile conflicts when profiles have matching labeled copies" do
    user = users(:three)
    stray = profiles(:stray)
    user.profiles.create!(name: "Stray (green)", copied_from: stray, labels: [ "green" ])

    prism = groups(:prism_circle)
    conflicts = prism.scan_for_conflicts([ "green" ])

    profile_conflicts = conflicts.select { |c| c[:original_type] == "Profile" }
    assert_equal 1, profile_conflicts.length
    assert_equal stray.id, profile_conflicts.first[:original_id]
    assert_equal "Stray (green)", profile_conflicts.first[:existing_copy_name]
  end

  test "scan_for_conflicts includes container_group_ids for profile conflicts" do
    user = users(:three)
    stray = profiles(:stray)
    user.profiles.create!(name: "Stray (green)", copied_from: stray, labels: [ "green" ])

    # Stray is in both prism_circle and rogue_pack
    prism = groups(:prism_circle)
    conflicts = prism.scan_for_conflicts([ "green" ])

    profile_conflicts = conflicts.select { |c| c[:original_type] == "Profile" }
    stray_conflict = profile_conflicts.find { |c| c[:original_id] == stray.id }
    assert_not_nil stray_conflict
    assert_includes stray_conflict[:container_group_ids], groups(:prism_circle).id
    assert_includes stray_conflict[:container_group_ids], groups(:rogue_pack).id
  end

  test "scan_for_conflicts returns both group and profile conflicts" do
    user = users(:three)
    rogue = groups(:rogue_pack)
    stray = profiles(:stray)

    user.groups.create!(name: "Rogue Pack (green)", copied_from: rogue, labels: [ "green" ])
    user.profiles.create!(name: "Stray (green)", copied_from: stray, labels: [ "green" ])

    prism = groups(:prism_circle)
    conflicts = prism.scan_for_conflicts([ "green" ])

    group_conflicts = conflicts.select { |c| c[:original_type] == "Group" }
    profile_conflicts = conflicts.select { |c| c[:original_type] == "Profile" }

    assert_equal 1, group_conflicts.length
    assert_equal rogue.id, group_conflicts.first[:original_id]

    assert profile_conflicts.any? { |c| c[:original_id] == stray.id }
  end

  test "scan_for_conflicts group conflicts come before profile conflicts" do
    user = users(:three)
    rogue = groups(:rogue_pack)
    stray = profiles(:stray)

    user.groups.create!(name: "Rogue Pack (green)", copied_from: rogue, labels: [ "green" ])
    user.profiles.create!(name: "Stray (green)", copied_from: stray, labels: [ "green" ])

    prism = groups(:prism_circle)
    conflicts = prism.scan_for_conflicts([ "green" ])

    group_index = conflicts.index { |c| c[:original_type] == "Group" }
    profile_index = conflicts.index { |c| c[:original_type] == "Profile" }
    assert group_index < profile_index, "Group conflicts should come before profile conflicts"
  end

  test "scan_for_conflicts deduplicates profile conflicts across groups" do
    user = users(:three)
    stray = profiles(:stray)
    user.profiles.create!(name: "Stray (green)", copied_from: stray, labels: [ "green" ])

    # Stray is in both prism_circle and rogue_pack within echo_shard's tree
    echo = groups(:echo_shard)
    conflicts = echo.scan_for_conflicts([ "green" ])

    profile_conflicts = conflicts.select { |c| c[:original_type] == "Profile" }
    stray_conflicts = profile_conflicts.select { |c| c[:original_id] == stray.id }
    assert_equal 1, stray_conflicts.length, "Stray should only appear once in profile conflicts"
  end

  test "scan_for_conflicts includes root group profiles in profile conflicts" do
    user = users(:three)
    mirage = profiles(:mirage)
    user.profiles.create!(name: "Mirage (green)", copied_from: mirage, labels: [ "green" ])

    # Mirage is directly in echo_shard (the root group for this duplication)
    echo = groups(:echo_shard)
    conflicts = echo.scan_for_conflicts([ "green" ])

    profile_conflicts = conflicts.select { |c| c[:original_type] == "Profile" }
    assert profile_conflicts.any? { |c| c[:original_id] == mirage.id },
           "Root group profile Mirage should be detected as a conflict"
  end

  test "scan_for_conflicts does not flag profiles without matching copies" do
    user = users(:three)
    stray = profiles(:stray)
    # Copy with different label
    user.profiles.create!(name: "Stray (red)", copied_from: stray, labels: [ "red" ])

    prism = groups(:prism_circle)
    conflicts = prism.scan_for_conflicts([ "green" ])

    profile_conflicts = conflicts.select { |c| c[:original_type] == "Profile" }
    assert_empty profile_conflicts
  end

  # -- deep_duplicate (Phase 6) --

  test "deep_duplicate with no conflicts creates correct groups and profiles" do
    echo = groups(:echo_shard)
    initial_group_count = Group.count
    initial_profile_count = Profile.count

    new_root = echo.deep_duplicate(new_labels: [ "blue" ])

    assert_not_nil new_root
    assert new_root.persisted?
    assert_equal [ "blue" ], new_root.labels
    assert_equal echo, new_root.copied_from
    assert_not_equal echo.uuid, new_root.uuid

    # Echo Shard tree: Echo Shard -> Prism Circle -> Rogue Pack
    # That's 3 groups total, plus profiles: Mirage (in echo_shard), Ember + Stray (in prism_circle), Stray (in rogue_pack)
    # Unique profiles: Mirage, Ember, Stray = 3
    assert_equal initial_group_count + 3, Group.count
    assert_equal initial_profile_count + 3, Profile.count
  end

  test "deep_duplicate copies have correct copied_from_id" do
    echo = groups(:echo_shard)
    new_root = echo.deep_duplicate(new_labels: [ "blue" ])

    assert_equal echo, new_root.copied_from

    # Check child groups
    prism_copy = Group.where(copied_from: groups(:prism_circle), labels: [ "blue" ].to_json).or(
      Group.where(copied_from: groups(:prism_circle)).where("labels @> ?", [ "blue" ].to_json)
    ).first
    assert_not_nil prism_copy, "Prism Circle should have been copied"
    assert_equal groups(:prism_circle), prism_copy.copied_from
  end

  test "deep_duplicate copies have new UUIDs" do
    echo = groups(:echo_shard)
    original_uuids = Group.where(id: echo.reachable_group_ids).pluck(:uuid)

    echo.deep_duplicate(new_labels: [ "test" ])

    new_groups = Group.where("labels @> ?", [ "test" ].to_json)
    new_groups.each do |g|
      assert_not_includes original_uuids, g.uuid, "Copied group should have a new UUID"
    end
  end

  test "deep_duplicate copies have the specified labels" do
    echo = groups(:echo_shard)
    echo.deep_duplicate(new_labels: [ "blue", "safe" ])

    new_groups = Group.where("labels @> ?", [ "blue", "safe" ].to_json).where.not(id: echo.reachable_group_ids)
    assert new_groups.count >= 3, "All copied groups should have the specified labels"

    new_profiles = Profile.where("labels @> ?", [ "blue", "safe" ].to_json)
    assert new_profiles.count >= 1, "Copied profiles should have the specified labels"
  end

  test "deep_duplicate recreates group-group edges" do
    echo = groups(:echo_shard)
    new_root = echo.deep_duplicate(new_labels: [ "blue" ])

    # Echo Shard (blue) should have Prism Circle (blue) as child
    assert_equal 1, new_root.child_groups.count
    prism_copy = new_root.child_groups.first
    assert_equal groups(:prism_circle), prism_copy.copied_from

    # Prism Circle (blue) should have Rogue Pack (blue) as child
    assert_equal 1, prism_copy.child_groups.count
    rogue_copy = prism_copy.child_groups.first
    assert_equal groups(:rogue_pack), rogue_copy.copied_from
  end

  test "deep_duplicate recreates group-profile links" do
    echo = groups(:echo_shard)
    new_root = echo.deep_duplicate(new_labels: [ "blue" ])

    # Echo Shard has Mirage
    mirage_copy = new_root.profiles.find { |p| p.copied_from == profiles(:mirage) }
    assert_not_nil mirage_copy, "Echo Shard copy should have Mirage copy"
  end

  test "deep_duplicate profiles appearing in multiple groups are copied once" do
    echo = groups(:echo_shard)
    echo.deep_duplicate(new_labels: [ "dup_test" ])

    # Stray appears in both prism_circle and rogue_pack
    stray_copies = Profile.where(copied_from: profiles(:stray)).where("labels @> ?", [ "dup_test" ].to_json)
    assert_equal 1, stray_copies.count, "Stray should be copied only once even though it appears in two groups"
  end

  test "deep_duplicate with reuse resolution links existing copy" do
    user = users(:three)
    prism = groups(:prism_circle)
    rogue = groups(:rogue_pack)

    # Pre-create copies
    prism_copy = user.groups.create!(name: "Prism Circle (blue)", copied_from: prism, labels: [ "blue" ])
    user.groups.create!(name: "Rogue Pack (blue)", copied_from: rogue, labels: [ "blue" ])

    echo = groups(:echo_shard)
    resolutions = { prism.id.to_s => "reuse" }

    initial_group_count = Group.count
    new_root = echo.deep_duplicate(new_labels: [ "blue" ], resolutions: resolutions)

    # Should have created only the root copy (Echo Shard blue)
    # Prism Circle is reused, and Rogue Pack is a descendant of reused Prism → skipped
    assert_equal initial_group_count + 1, Group.count

    # The reused Prism Circle copy should be linked as a child
    assert_includes new_root.child_groups.map(&:id), prism_copy.id
  end

  test "deep_duplicate with reuse resolution skips descendants of reused group" do
    user = users(:three)
    prism = groups(:prism_circle)
    rogue = groups(:rogue_pack)

    user.groups.create!(name: "Prism Circle (blue)", copied_from: prism, labels: [ "blue" ])
    rogue_copy = user.groups.create!(name: "Rogue Pack (blue)", copied_from: rogue, labels: [ "blue" ])

    echo = groups(:echo_shard)
    resolutions = { prism.id.to_s => "reuse" }

    echo.deep_duplicate(new_labels: [ "blue" ], resolutions: resolutions)

    # Since Prism was reused and Rogue is a descendant, no new Rogue copy should exist
    # beyond the pre-created one
    rogue_copies = Group.where(copied_from: rogue).where("labels @> ?", [ "blue" ].to_json)
    assert_equal 1, rogue_copies.count, "Rogue Pack should not have been duplicated again"
    assert_equal rogue_copy.id, rogue_copies.first.id
  end

  test "deep_duplicate recreates inclusion overrides with remapped paths" do
    # Alpha Clan has an override: hide Rogue Pack at [spectrum, prism_circle]
    alpha = groups(:alpha_clan)
    initial_override_count = InclusionOverride.count

    new_root = alpha.deep_duplicate(new_labels: [ "override_test" ])

    new_overrides = InclusionOverride.where(group_id: new_root.reachable_group_ids)
                                     .where.not(group_id: alpha.reachable_group_ids)

    # The original has overrides on alpha_clan; the copy should have remapped overrides
    # on the freshly-copied groups
    assert new_overrides.count > 0 || InclusionOverride.count > initial_override_count,
           "Inclusion overrides should be recreated for freshly copied groups"
  end

  # -- deep_duplicate with profile_resolutions --

  test "deep_duplicate with profile reuse resolution links existing profile copy" do
    user = users(:three)
    stray = profiles(:stray)
    stray_copy = user.profiles.create!(name: "Stray (green)", copied_from: stray, labels: [ "green" ])

    prism = groups(:prism_circle)
    profile_resolutions = { stray.id.to_s => "reuse" }

    initial_profile_count = Profile.count
    new_root = prism.deep_duplicate(new_labels: [ "green" ], profile_resolutions: profile_resolutions)

    # Stray should be reused, not copied again
    stray_copies = Profile.where(copied_from: stray).where("labels @> ?", [ "green" ].to_json)
    assert_equal 1, stray_copies.count, "Stray should not have been duplicated again"
    assert_equal stray_copy.id, stray_copies.first.id

    # But other profiles (Ember) should be freshly copied
    ember_copies = Profile.where(copied_from: profiles(:ember)).where("labels @> ?", [ "green" ].to_json)
    assert_equal 1, ember_copies.count, "Ember should have been freshly copied"
  end

  test "deep_duplicate with profile reuse links the reused profile in group_profiles" do
    user = users(:three)
    stray = profiles(:stray)
    stray_copy = user.profiles.create!(name: "Stray (green)", copied_from: stray, labels: [ "green" ])

    prism = groups(:prism_circle)
    profile_resolutions = { stray.id.to_s => "reuse" }

    new_root = prism.deep_duplicate(new_labels: [ "green" ], profile_resolutions: profile_resolutions)

    # The reused stray copy should appear as a profile in the new prism copy
    assert_includes new_root.profile_ids, stray_copy.id,
                    "Reused Stray copy should be linked to the new Prism Circle copy"
  end

  test "deep_duplicate with profile copy resolution creates a fresh copy" do
    user = users(:three)
    stray = profiles(:stray)
    user.profiles.create!(name: "Stray (green)", copied_from: stray, labels: [ "green" ])

    prism = groups(:prism_circle)
    profile_resolutions = { stray.id.to_s => "copy" }

    new_root = prism.deep_duplicate(new_labels: [ "green" ], profile_resolutions: profile_resolutions)

    # Stray should have been copied (creating a second copy)
    stray_copies = Profile.where(copied_from: stray).where("labels @> ?", [ "green" ].to_json)
    assert_equal 2, stray_copies.count, "A new copy of Stray should have been created"

    # The new copy should be in the new prism group
    new_stray = new_root.profiles.find { |p| p.copied_from == stray }
    assert_not_nil new_stray
  end

  test "deep_duplicate reused profile appears in all fresh groups that contain it" do
    user = users(:three)
    stray = profiles(:stray)
    stray_copy = user.profiles.create!(name: "Stray (green)", copied_from: stray, labels: [ "green" ])

    # Echo Shard -> Prism Circle -> Rogue Pack
    # Stray is in both prism_circle and rogue_pack
    echo = groups(:echo_shard)
    profile_resolutions = { stray.id.to_s => "reuse" }

    new_root = echo.deep_duplicate(new_labels: [ "green" ], profile_resolutions: profile_resolutions)

    # Find the new prism and rogue copies
    prism_copy = new_root.child_groups.find { |g| g.copied_from == groups(:prism_circle) }
    rogue_copy = prism_copy.child_groups.find { |g| g.copied_from == groups(:rogue_pack) }

    # The reused stray copy should be in both
    assert_includes prism_copy.profile_ids, stray_copy.id
    assert_includes rogue_copy.profile_ids, stray_copy.id
  end

  # -- duplication_preview_tree --

  test "duplication_preview_tree returns all child groups with action new when no resolutions" do
    echo = groups(:echo_shard)
    tree = echo.duplication_preview_tree(labels: [ "blue" ], resolutions: {})

    group_names = tree.map { |n| n[:group].name }
    assert_includes group_names, "Prism Circle"

    tree.each do |node|
      assert_equal "new", node[:action]
    end
  end

  test "duplication_preview_tree includes profiles with action new" do
    echo = groups(:echo_shard)
    tree = echo.duplication_preview_tree(labels: [ "blue" ], resolutions: {})

    prism_node = tree.find { |n| n[:group] == groups(:prism_circle) }
    assert prism_node, "Prism Circle should be in the tree"

    profile_names = prism_node[:profiles].map { |e| e[:profile].name }
    assert_includes profile_names, "Ember"
    assert_includes profile_names, "Stray"

    prism_node[:profiles].each do |entry|
      assert_equal "new", entry[:action]
    end
  end

  test "duplication_preview_tree marks reused groups when resolution is reuse" do
    user = users(:three)
    prism = groups(:prism_circle)
    user.groups.create!(name: "Prism Copy", copied_from: prism, labels: [ "blue" ])

    echo = groups(:echo_shard)
    resolutions = { prism.id.to_s => "reuse" }
    tree = echo.duplication_preview_tree(labels: [ "blue" ], resolutions: resolutions)

    prism_node = tree.find { |n| n[:group] == prism }
    assert prism_node
    assert_equal "reuse", prism_node[:action]
    assert prism_node[:directly_reused]
    assert_not_nil prism_node[:reuse_target]
    assert_equal "Prism Copy", prism_node[:reuse_target].name
  end

  test "duplication_preview_tree marks descendants of reused groups as reuse" do
    user = users(:three)
    prism = groups(:prism_circle)
    user.groups.create!(name: "Prism Copy", copied_from: prism, labels: [ "blue" ])

    echo = groups(:echo_shard)
    resolutions = { prism.id.to_s => "reuse" }
    tree = echo.duplication_preview_tree(labels: [ "blue" ], resolutions: resolutions)

    prism_node = tree.find { |n| n[:group] == prism }
    rogue_node = prism_node[:children].find { |n| n[:group] == groups(:rogue_pack) }
    assert rogue_node
    assert_equal "reuse", rogue_node[:action]
    assert_not rogue_node[:directly_reused], "Rogue Pack is inherited reuse, not directly reused"
    assert_nil rogue_node[:reuse_target]
  end

  test "duplication_preview_tree profiles inherit reuse action from reused parent" do
    user = users(:three)
    prism = groups(:prism_circle)
    user.groups.create!(name: "Prism Copy", copied_from: prism, labels: [ "blue" ])

    echo = groups(:echo_shard)
    resolutions = { prism.id.to_s => "reuse" }
    tree = echo.duplication_preview_tree(labels: [ "blue" ], resolutions: resolutions)

    prism_node = tree.find { |n| n[:group] == prism }
    prism_node[:profiles].each do |entry|
      assert_equal "reuse", entry[:action], "Profile #{entry[:profile].name} should inherit reuse action"
    end
  end

  test "duplication_preview_tree includes hidden flags from source overrides" do
    # Castle Clan has overrides: static_burst hidden in flux, drift hidden in flux, ripple hidden in flux
    castle = groups(:castle_clan)
    tree = castle.duplication_preview_tree(labels: [ "blue" ], resolutions: {})

    flux_node = tree.find { |n| n[:group] == groups(:flux) }
    assert flux_node, "Flux should be in the tree"

    # Static Burst is hidden at the flux level
    static_node = flux_node[:children].find { |n| n[:group] == groups(:static_burst) }
    assert static_node, "Static Burst should be a child of Flux"
    assert static_node[:hidden], "Static Burst should be marked hidden"

    # Drift profile is hidden in flux
    drift_entry = flux_node[:profiles].find { |e| e[:profile] == profiles(:drift) }
    assert drift_entry, "Drift should be a profile in Flux"
    assert drift_entry[:hidden], "Drift should be marked hidden"

    # Ripple profile is hidden in flux
    ripple_entry = flux_node[:profiles].find { |e| e[:profile] == profiles(:ripple) }
    assert ripple_entry, "Ripple should be a profile in Flux"
    assert ripple_entry[:hidden], "Ripple should be marked hidden"
  end

  test "duplication_preview_tree cascade_hidden propagates to children" do
    castle = groups(:castle_clan)
    tree = castle.duplication_preview_tree(labels: [ "blue" ], resolutions: {})

    flux_node = tree.find { |n| n[:group] == groups(:flux) }
    static_node = flux_node[:children].find { |n| n[:group] == groups(:static_burst) }

    # Static Burst itself is hidden, so its profiles should be cascade_hidden
    static_node[:profiles].each do |entry|
      assert entry[:cascade_hidden], "Profile #{entry[:profile].name} in Static Burst should be cascade-hidden"
    end
  end

  test "duplication_preview_tree non-hidden group has hidden false" do
    echo = groups(:echo_shard)
    tree = echo.duplication_preview_tree(labels: [ "blue" ], resolutions: {})

    prism_node = tree.find { |n| n[:group] == groups(:prism_circle) }
    assert_not prism_node[:hidden], "Prism Circle should not be hidden in echo_shard tree"
    assert_not prism_node[:cascade_hidden], "Prism Circle should not be cascade-hidden"
  end

  test "duplication_preview_tree returns nested children" do
    echo = groups(:echo_shard)
    tree = echo.duplication_preview_tree(labels: [ "blue" ], resolutions: {})

    prism_node = tree.find { |n| n[:group] == groups(:prism_circle) }
    child_names = prism_node[:children].map { |n| n[:group].name }
    assert_includes child_names, "Rogue Pack"
  end

  # -- duplication_preview_tree with profile_resolutions --

  test "duplication_preview_tree marks profiles as reused when profile_resolutions say reuse" do
    user = users(:three)
    stray = profiles(:stray)
    stray_copy = user.profiles.create!(name: "Stray (green)", copied_from: stray, labels: [ "green" ])

    echo = groups(:echo_shard)
    profile_resolutions = { stray.id.to_s => "reuse" }
    tree = echo.duplication_preview_tree(labels: [ "green" ], resolutions: {}, profile_resolutions: profile_resolutions)

    prism_node = tree.find { |n| n[:group] == groups(:prism_circle) }
    stray_entry = prism_node[:profiles].find { |e| e[:profile] == stray }
    assert_not_nil stray_entry
    assert_equal "reuse", stray_entry[:action]
    assert stray_entry[:directly_reused]
    assert_equal stray_copy, stray_entry[:reuse_target]
  end

  test "duplication_preview_tree profiles without resolution are marked new" do
    echo = groups(:echo_shard)
    tree = echo.duplication_preview_tree(labels: [ "green" ], resolutions: {}, profile_resolutions: {})

    prism_node = tree.find { |n| n[:group] == groups(:prism_circle) }
    prism_node[:profiles].each do |entry|
      assert_equal "new", entry[:action]
      assert_not entry[:directly_reused]
      assert_nil entry[:reuse_target]
    end
  end

  test "duplication_preview_tree profiles in reused groups stay reuse regardless of profile_resolutions" do
    user = users(:three)
    prism = groups(:prism_circle)
    stray = profiles(:stray)
    user.groups.create!(name: "Prism Copy", copied_from: prism, labels: [ "green" ])
    user.profiles.create!(name: "Stray (green)", copied_from: stray, labels: [ "green" ])

    echo = groups(:echo_shard)
    resolutions = { prism.id.to_s => "reuse" }
    profile_resolutions = { stray.id.to_s => "copy" }
    tree = echo.duplication_preview_tree(labels: [ "green" ], resolutions: resolutions, profile_resolutions: profile_resolutions)

    prism_node = tree.find { |n| n[:group] == prism }
    # Profile in reused group should still be "reuse" (parent group action takes precedence)
    prism_node[:profiles].each do |entry|
      assert_equal "reuse", entry[:action], "Profile #{entry[:profile].name} in reused group should be reuse"
    end
  end

  # -- stale reuse targets --

  # -- deep_duplicate avatar blob sharing ----------------------------------------

  test "deep_duplicate shares the avatar blob with the new group copy" do
    source = groups(:echo_shard)
    source.avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert source.avatar.attached?

    new_root = source.deep_duplicate(new_labels: [ "avatar_blob_test" ])

    assert new_root.avatar.attached?, "duplicated group should have an avatar"
    assert_equal source.avatar.blob.id, new_root.avatar.blob.id,
      "duplicated group should share the same blob, not upload a new file"
  end

  test "deep_duplicate shares avatar blobs with new profile copies" do
    source_profile = profiles(:mirage)
    source_profile.avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert source_profile.avatar.attached?

    echo = groups(:echo_shard)
    echo.deep_duplicate(new_labels: [ "avatar_profile_blob_test" ])

    new_profile = Profile.find_by(copied_from_id: source_profile.id)
    assert_not_nil new_profile, "a copy of the profile should have been created"
    assert new_profile.avatar.attached?, "duplicated profile should have an avatar"
    assert_equal source_profile.avatar.blob.id, new_profile.avatar.blob.id,
      "duplicated profile should share the same blob"
  end

  test "detaching avatar on duplicated group does not remove original avatar" do
    source = groups(:echo_shard)
    source.avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )

    new_root = source.deep_duplicate(new_labels: [ "detach_test" ])
    assert new_root.avatar.attached?

    new_root.avatar.detach

    source.reload
    assert source.avatar.attached?, "original avatar should be unaffected after detaching the copy's avatar"
  end

  test "purging avatar on duplicated group does not purge the shared blob while original still references it" do
    source = groups(:echo_shard)
    source.avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    shared_blob_id = source.avatar.blob.id

    new_root = source.deep_duplicate(new_labels: [ "purge_blob_test" ])
    assert new_root.avatar.attached?

    # Purging the copy's attachment should NOT destroy the blob because the
    # original attachment still references it.
    new_root.avatar.purge

    assert source.reload.avatar.attached?, "original avatar should still be attached after purging copy"
    assert ActiveStorage::Blob.exists?(shared_blob_id),
      "shared blob should still exist in the database while the original attachment references it"
  end

  # -- stale reuse targets --

  test "duplication_preview_tree downgrades group to new when reuse target no longer exists" do
    user = users(:three)
    prism = groups(:prism_circle)

    # Simulate the scan step finding a copy, yielding a "reuse" resolution
    copy = user.groups.create!(name: "Prism Copy", copied_from: prism, labels: [ "blue" ])
    resolutions = { prism.id.to_s => "reuse" }

    # The copy disappears before the confirm step (deleted or labels changed)
    copy.destroy!

    echo = groups(:echo_shard)
    tree = echo.duplication_preview_tree(labels: [ "blue" ], resolutions: resolutions)

    prism_node = tree.find { |n| n[:group] == prism }
    assert prism_node
    assert_equal "new", prism_node[:action],
      "Group should be downgraded to 'new' when the reuse target no longer exists"
    assert_not prism_node[:directly_reused]
    assert_nil prism_node[:reuse_target]
  end

  test "duplication_preview_tree downgrades profile to new when reuse target no longer exists" do
    user = users(:three)
    stray = profiles(:stray)

    # Simulate the scan step finding a copy, yielding a "reuse" resolution
    copy = user.profiles.create!(name: "Stray (blue)", copied_from: stray, labels: [ "blue" ])
    profile_resolutions = { stray.id.to_s => "reuse" }

    # The copy disappears before the confirm step
    copy.destroy!

    echo = groups(:echo_shard)
    tree = echo.duplication_preview_tree(labels: [ "blue" ], resolutions: {}, profile_resolutions: profile_resolutions)

    prism_node = tree.find { |n| n[:group] == groups(:prism_circle) }
    stray_entry = prism_node[:profiles].find { |e| e[:profile] == stray }
    assert stray_entry
    assert_equal "new", stray_entry[:action],
      "Profile should be downgraded to 'new' when the reuse target no longer exists"
    assert_not stray_entry[:directly_reused]
    assert_nil stray_entry[:reuse_target]
  end
end
