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

  # Timestamp validations

  test "created_at in the past is valid" do
    group = Group.new(user: users(:one), name: "Test", created_at: 1.day.ago)
    group.valid?
    assert_empty group.errors[:created_at]
  end

  test "created_at in the future is invalid" do
    group = Group.new(user: users(:one), name: "Test", created_at: 2.minutes.from_now)
    assert_not group.valid?
    assert_includes group.errors[:created_at], "can't be in the future"
  end

  test "has many profiles through group_profiles" do
    assert_includes groups(:friends).profiles, profiles(:alice)
  end

  test "can attach avatar" do
    group = groups(:friends)
    group.avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert group.avatar.attached?
  end

  test "rejects non-image avatar" do
    group = groups(:friends)
    group.avatar.attach(
      io: StringIO.new("<script>alert('xss')</script>"),
      filename: "evil.html",
      content_type: "text/html"
    )
    assert_not group.valid?
    assert_includes group.errors[:avatar], "must be a JPG/JPEG, PNG, or WebP image"
  end

  test "rejects avatar over 2 MB" do
    group = groups(:friends)
    group.avatar.attach(
      io: StringIO.new("a" * (HasAvatar::AVATAR_MAX_SIZE + 1)),
      filename: "toobig.png",
      content_type: "image/png"
    )
    assert_not group.valid?
    assert_includes group.errors[:avatar], "must be 2 MB or less"
  end

  test "has many child_groups" do
    everyone = groups(:everyone)
    assert_includes everyone.child_groups, groups(:friends)
  end

  test "has many parent_groups" do
    friends = groups(:friends)
    assert_includes friends.parent_groups, groups(:everyone)
  end

  test "all_profiles includes profiles from child groups" do
    everyone = groups(:everyone)
    # everyone has no direct profiles, but friends (its child) has alice
    all = everyone.all_profiles
    assert_includes all, profiles(:alice)
  end

  test "all_profiles de-duplicates profiles appearing in multiple sub-groups" do
    everyone = groups(:everyone)
    alice = profiles(:alice)

    # Add alice directly to everyone too (she's already in friends, a child)
    everyone.profiles << alice

    all = everyone.all_profiles
    assert_equal 1, all.where(id: alice.id).count
  end

  test "all_child_groups returns all descendants" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)
    coworkers = user.groups.create!(name: "Coworkers")
    GroupGroup.create!(parent_group: friends, child_group: coworkers)

    descendants = everyone.all_child_groups
    assert_includes descendants, friends
    assert_includes descendants, coworkers
  end

  test "descendant_sections returns depth-first ordered groups with profiles" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)
    # Build: everyone → friends, everyone → zoo, friends → close
    zoo = user.groups.create!(name: "Zoo Group")
    close = user.groups.create!(name: "Close Friends")
    GroupGroup.create!(parent_group: everyone, child_group: zoo)
    GroupGroup.create!(parent_group: friends, child_group: close)

    sections = everyone.descendant_sections
    names = sections.map(&:name)
    # Depth-first alphabetical: Close Friends (under Friends), then Friends, then Zoo Group
    assert_equal [ "Friends", "Close Friends", "Zoo Group" ], names
  end

  test "descendant_sections eager-loads profiles" do
    everyone = groups(:everyone)
    sections = everyone.descendant_sections
    # profiles should be pre-loaded — no additional query
    assert sections.first.profiles.loaded?
  end

  test "descendant_tree returns nested structure with children" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)
    # Build: everyone → friends → close
    close = user.groups.create!(name: "Close Friends")
    GroupGroup.create!(parent_group: friends, child_group: close)
    close.profiles << profiles(:alice)

    tree = everyone.descendant_tree
    assert_equal 1, tree.length
    # Top level: Friends
    assert_equal "Friends", tree.first[:group].name
    # Friends has child: Close Friends
    assert_equal 1, tree.first[:children].length
    assert_equal "Close Friends", tree.first[:children].first[:group].name
    # Close Friends has Alice (as a tagged profile entry)
    profile_entries = tree.first[:children].first[:profiles]
    assert_equal [ "Alice" ], profile_entries.map { |e| e[:profile].name }
    assert_equal [ false ], profile_entries.map { |e| e[:repeated] }
  end

  # -- Overlapping relationship type --

  test "descendant_group_ids includes overlapping child but not its children" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)
    # Build: everyone →(nested) friends →(nested) close
    close = user.groups.create!(name: "Close Friends")
    GroupGroup.create!(parent_group: friends, child_group: close)

    # With nested, everyone sees all three
    assert_includes everyone.descendant_group_ids, friends.id
    assert_includes everyone.descendant_group_ids, close.id

    # Now change friends to overlapping inside everyone
    link = GroupGroup.find_by(parent_group: everyone, child_group: friends)
    link.update!(inclusion_mode: "none")

    ids = everyone.descendant_group_ids
    # Friends is still included (it's a direct child)
    assert_includes ids, friends.id
    # But Close Friends is NOT included (recursion stops at overlapping)
    assert_not_includes ids, close.id
  end

  test "all_profiles excludes profiles from groups behind overlapping boundary" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)
    close = user.groups.create!(name: "Close Friends")
    GroupGroup.create!(parent_group: friends, child_group: close)
    close.profiles << profiles(:bob)

    # With nested, everyone sees Bob (through friends → close)
    assert_includes everyone.all_profiles, profiles(:bob)

    # Change friends to overlapping
    link = GroupGroup.find_by(parent_group: everyone, child_group: friends)
    link.update!(inclusion_mode: "none")

    # Now Bob (in Close Friends) is not visible from everyone
    assert_not_includes everyone.all_profiles, profiles(:bob)
    # But Alice (directly in friends) is still visible
    assert_includes everyone.all_profiles, profiles(:alice)
  end

  test "descendant_tree marks overlapping nodes and omits their children" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)
    close = user.groups.create!(name: "Close Friends")
    GroupGroup.create!(parent_group: friends, child_group: close)

    # With nested, tree includes close under friends
    tree = everyone.descendant_tree
    assert_equal 1, tree.first[:children].length
    assert_not tree.first[:overlapping]

    # Change friends to overlapping
    link = GroupGroup.find_by(parent_group: everyone, child_group: friends)
    link.update!(inclusion_mode: "none")

    tree = everyone.descendant_tree
    friends_node = tree.first
    # Friends is marked as overlapping
    assert friends_node[:overlapping]
    # Its children are empty (recursion stopped)
    assert_empty friends_node[:children]
  end

  test "descendant_sections stops recursion at overlapping groups" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)
    close = user.groups.create!(name: "Close Friends")
    GroupGroup.create!(parent_group: friends, child_group: close)

    # With nested, sections include both friends and close
    sections = everyone.descendant_sections
    assert_equal [ "Friends", "Close Friends" ], sections.map(&:name)

    # Change friends to overlapping
    link = GroupGroup.find_by(parent_group: everyone, child_group: friends)
    link.update!(inclusion_mode: "none")

    # Now only friends appears (close is behind the overlapping boundary)
    sections = everyone.descendant_sections
    assert_equal [ "Friends" ], sections.map(&:name)
  end

  test "overlapping group is still fully visible when viewed directly" do
    user = users(:one)
    friends = groups(:friends)
    close = user.groups.create!(name: "Close Friends")
    GroupGroup.create!(parent_group: friends, child_group: close)
    close.profiles << profiles(:bob)

    # Viewing friends directly still shows close and its profiles
    assert_includes friends.descendant_group_ids, close.id
    assert_includes friends.all_profiles, profiles(:bob)
    assert_equal [ "Close Friends" ], friends.descendant_tree.map { |n| n[:group].name }
  end

  # -- Repeated profile tracking --

  test "descendant_tree marks profiles as repeated when they appear in multiple groups" do
    user = users(:one)
    everyone = groups(:everyone)
    friends = groups(:friends)
    close = user.groups.create!(name: "Close Friends")
    GroupGroup.create!(parent_group: friends, child_group: close)

    alice = profiles(:alice)
    # Alice is in friends (via fixture) and also in close
    close.profiles << alice

    tree = everyone.descendant_tree
    friends_node = tree.first
    close_node = friends_node[:children].first

    # Alice appears first under Close Friends (alphabetically Close < Friends in depth-first)
    close_entries = close_node[:profiles]
    friends_entries = friends_node[:profiles]

    close_alice = close_entries.find { |e| e[:profile].id == alice.id }
    friends_alice = friends_entries.find { |e| e[:profile].id == alice.id }

    # First occurrence is not repeated
    assert_not close_alice[:repeated], "First occurrence of Alice should not be marked as repeated"
    # Second occurrence IS repeated
    assert friends_alice[:repeated], "Second occurrence of Alice should be marked as repeated"
  end

  test "descendant_tree seen_profile_ids set is populated for root-level tracking" do
    everyone = groups(:everyone)
    alice = profiles(:alice)

    seen = Set.new
    everyone.descendant_tree(seen_profile_ids: seen)

    # Alice is in friends (a descendant) so she should be in the seen set
    assert_includes seen, alice.id
  end

  test "descendant_tree profiles appearing only once are not marked as repeated" do
    everyone = groups(:everyone)

    tree = everyone.descendant_tree
    friends_node = tree.first
    alice_entry = friends_node[:profiles].find { |e| e[:profile].id == profiles(:alice).id }

    assert_not alice_entry[:repeated], "Profile appearing once should not be marked as repeated"
  end

  # -- selected inclusion mode --
  #
  # The "selected" edge type means: show this child group, but only recurse into
  # the sub-groups explicitly listed in `included_subgroup_ids` on that edge.
  # Each of those sub-groups then follows its own edge's inclusion_mode for
  # further recursion.

  test "descendant_sections: groups not in included_subgroup_ids are omitted entirely" do
    user = users(:one)
    root = user.groups.create!(name: "Root")
    a    = user.groups.create!(name: "Alpha")
    x    = user.groups.create!(name: "Excluded")

    # root →(selected, included=[])→ a  means: show a, but none of a's sub-groups
    GroupGroup.create!(parent_group: root, child_group: a,
                       inclusion_mode: "selected", included_subgroup_ids: [])
    # a →(all)→ x  but x is not in root→a's included list
    GroupGroup.create!(parent_group: a, child_group: x, inclusion_mode: "all")

    names = root.descendant_sections.map(&:name)
    assert_includes     names, "Alpha",    "Alpha (the selected child) should appear"
    assert_not_includes names, "Excluded", "Excluded is not in included_subgroup_ids so must not appear"
  end

  test "descendant_sections: selected sub-group with none sub-edge appears but its children do not" do
    user = users(:one)
    root     = user.groups.create!(name: "Root")
    a        = user.groups.create!(name: "Alpha")
    b        = user.groups.create!(name: "Beta")
    b_child  = user.groups.create!(name: "BetaChild")

    # root →(selected, included=[b])→ a
    GroupGroup.create!(parent_group: root, child_group: a,
                       inclusion_mode: "selected", included_subgroup_ids: [ b.id ])
    # a →(none)→ b  — b is in the selected list, but its own edge is "none"
    GroupGroup.create!(parent_group: a, child_group: b, inclusion_mode: "none")
    # b →(all)→ b_child  — would normally recurse, but the "none" edge stops it
    GroupGroup.create!(parent_group: b, child_group: b_child, inclusion_mode: "all")

    names = root.descendant_sections.map(&:name)
    assert_includes     names, "Alpha",     "Alpha should appear"
    assert_includes     names, "Beta",      "Beta (none-edge, in selected list) should appear"
    assert_not_includes names, "BetaChild", "BetaChild must be hidden — none edge stops recursion"
  end

  test "descendant_tree: selected sub-group with none sub-edge is marked overlapping with no children" do
    user = users(:one)
    root    = user.groups.create!(name: "Root")
    a       = user.groups.create!(name: "Alpha")
    b       = user.groups.create!(name: "Beta")
    b_child = user.groups.create!(name: "BetaChild")

    GroupGroup.create!(parent_group: root, child_group: a,
                       inclusion_mode: "selected", included_subgroup_ids: [ b.id ])
    GroupGroup.create!(parent_group: a, child_group: b, inclusion_mode: "none")
    GroupGroup.create!(parent_group: b, child_group: b_child, inclusion_mode: "all")

    tree = root.descendant_tree
    alpha_node = tree.find { |n| n[:group].name == "Alpha" }
    assert alpha_node, "Alpha should appear in tree"

    beta_node = alpha_node[:children].find { |n| n[:group].name == "Beta" }
    assert beta_node, "Beta should appear as a child of Alpha"
    assert beta_node[:overlapping],      "Beta with none-edge should be marked as overlapping"
    assert_empty beta_node[:children],   "Beta with none-edge should have no children rendered"
  end

  test "descendant_sections: selected sub-group with selected sub-edge excludes IDs not in its list" do
    user = users(:one)
    root    = user.groups.create!(name: "Root")
    a       = user.groups.create!(name: "Alpha")
    b       = user.groups.create!(name: "Beta")
    charlie = user.groups.create!(name: "Charlie")  # in b's selected list
    delta   = user.groups.create!(name: "Delta")    # NOT in b's selected list

    # root →(selected, included=[b])→ a
    GroupGroup.create!(parent_group: root, child_group: a,
                       inclusion_mode: "selected", included_subgroup_ids: [ b.id ])
    # a →(selected, included=[charlie])→ b  — b's own edge is also "selected"
    GroupGroup.create!(parent_group: a, child_group: b,
                       inclusion_mode: "selected", included_subgroup_ids: [ charlie.id ])
    GroupGroup.create!(parent_group: b, child_group: charlie, inclusion_mode: "all")
    GroupGroup.create!(parent_group: b, child_group: delta,   inclusion_mode: "all")

    names = root.descendant_sections.map(&:name)
    assert_includes     names, "Alpha", "Alpha should appear"
    assert_includes     names, "Beta",  "Beta (in root→a's selected list) should appear"
    # Delta is a child of Beta but is not in Beta's own included_subgroup_ids —
    # it must be absent regardless of its own edge type.
    assert_not_includes names, "Delta", "Delta (not in Beta's included list) must not appear"
  end

  test "descendant_tree: selected sub-group with selected sub-edge excludes IDs not in its list" do
    user = users(:one)
    root    = user.groups.create!(name: "Root")
    a       = user.groups.create!(name: "Alpha")
    b       = user.groups.create!(name: "Beta")
    charlie = user.groups.create!(name: "Charlie")
    delta   = user.groups.create!(name: "Delta")

    GroupGroup.create!(parent_group: root, child_group: a,
                       inclusion_mode: "selected", included_subgroup_ids: [ b.id ])
    GroupGroup.create!(parent_group: a, child_group: b,
                       inclusion_mode: "selected", included_subgroup_ids: [ charlie.id ])
    GroupGroup.create!(parent_group: b, child_group: charlie, inclusion_mode: "all")
    GroupGroup.create!(parent_group: b, child_group: delta,   inclusion_mode: "all")

    tree = root.descendant_tree
    alpha_node = tree.find { |n| n[:group].name == "Alpha" }
    assert alpha_node, "Alpha should appear"

    beta_node = alpha_node[:children].find { |n| n[:group].name == "Beta" }
    assert beta_node, "Beta should appear as child of Alpha"
    assert_not beta_node[:overlapping], "Beta with selected-edge should not be marked as overlapping"

    child_names = beta_node[:children].map { |n| n[:group].name }
    assert_not_includes child_names, "Delta",
      "Delta (not in Beta's included_subgroup_ids) must not appear under Beta"
  end

  test "descendant_sections: selected sub-group with all sub-edge includes deeper children" do
    user = users(:one)
    root     = user.groups.create!(name: "Root")
    a        = user.groups.create!(name: "Alpha")
    b        = user.groups.create!(name: "Beta")
    b_child  = user.groups.create!(name: "BetaChild")

    # root →(selected, included=[b])→ a
    GroupGroup.create!(parent_group: root, child_group: a,
                       inclusion_mode: "selected", included_subgroup_ids: [ b.id ])
    # a →(all)→ b  — b is in the selected list and its sub-edge is "all"
    GroupGroup.create!(parent_group: a, child_group: b, inclusion_mode: "all")
    # b →(all)→ b_child
    GroupGroup.create!(parent_group: b, child_group: b_child, inclusion_mode: "all")

    names = root.descendant_sections.map(&:name)
    assert_includes names, "Alpha",     "Alpha should appear"
    assert_includes names, "Beta",      "Beta (all sub-edge, in selected list) should appear"
    assert_includes names, "BetaChild", "BetaChild should appear — Beta is included and has an all sub-edge"
  end

  # -- include_direct_profiles flag --
  #
  # include_direct_profiles controls whether a child group's own direct profiles
  # are pulled into the parent's visible set. Sub-groups and their profiles are
  # unaffected — only the immediate profiles of the child group are suppressed.
  #
  # The fixtures already encode this scenario via castle_clan → flux:
  #   inclusion_mode: selected, included_subgroup_ids: [echo_shard], include_direct_profiles: false
  # drift and ripple are direct flux members; mirage is in echo_shard.

  test "all_profiles excludes direct profiles of child when include_direct_profiles is false" do
    castle = groups(:castle_clan)
    assert_not_includes castle.all_profiles, profiles(:drift),
      "Drift (direct flux member) should be excluded because include_direct_profiles is false"
    assert_not_includes castle.all_profiles, profiles(:ripple),
      "Ripple (direct flux member) should be excluded because include_direct_profiles is false"
  end

  test "all_profiles still includes sub-group profiles when include_direct_profiles is false" do
    # echo_shard is in flux's selected list and has include_direct_profiles defaulting to true;
    # mirage (in echo_shard) must be visible from castle_clan even though flux's own profiles aren't
    castle = groups(:castle_clan)
    assert_includes castle.all_profiles, profiles(:mirage),
      "Mirage (in echo_shard, a selected sub-group of flux) should be visible from castle_clan"
  end

  test "descendant_tree shows empty profiles array for node with include_direct_profiles false" do
    castle = groups(:castle_clan)
    tree = castle.descendant_tree
    flux_node = tree.find { |n| n[:group].name == "Flux" }
    assert flux_node, "Flux should appear in castle_clan's tree"
    assert_empty flux_node[:profiles],
      "Flux's profiles should be empty when include_direct_profiles is false on the edge"
  end

  test "descendant_tree still recurses into children when include_direct_profiles is false" do
    # include_direct_profiles only suppresses the node's own profiles; sub-group children are unaffected
    castle = groups(:castle_clan)
    tree = castle.descendant_tree
    flux_node = tree.find { |n| n[:group].name == "Flux" }
    assert flux_node, "Flux should appear in castle_clan's tree"
    child_names = flux_node[:children].map { |n| n[:group].name }
    assert_includes child_names, "Echo Shard",
      "Echo Shard (in included_subgroup_ids) should still appear as a child of Flux"
  end

  test "descendant_tree includes profiles in sub-groups of a node with include_direct_profiles false" do
    castle = groups(:castle_clan)
    tree = castle.descendant_tree
    flux_node = tree.find { |n| n[:group].name == "Flux" }
    echo_node = flux_node&.dig(:children)&.find { |n| n[:group].name == "Echo Shard" }
    assert echo_node, "Echo Shard should appear under Flux in castle_clan's tree"
    profile_names = echo_node[:profiles].map { |e| e[:profile].name }
    assert_includes profile_names, "Mirage",
      "Mirage (in echo_shard) should be visible even though Flux has include_direct_profiles false"
  end

  test "descendant_tree shows profiles when include_direct_profiles is true (default)" do
    # everyone → friends has no explicit include_direct_profiles (defaults to true)
    everyone = groups(:everyone)
    tree = everyone.descendant_tree
    friends_node = tree.find { |n| n[:group].name == "Friends" }
    assert friends_node, "Friends should appear in everyone's tree"
    profile_names = friends_node[:profiles].map { |e| e[:profile].name }
    assert_includes profile_names, "Alice",
      "Alice should appear in Friends' profiles when include_direct_profiles is true"
  end

  test "all_profiles respects include_direct_profiles false on an all-mode edge" do
    user = users(:one)
    parent = user.groups.create!(name: "Parent Group")
    child  = user.groups.create!(name: "Child Group")
    grandchild = user.groups.create!(name: "Grandchild Group")
    child_profile = user.profiles.create!(name: "Child Profile")
    grandchild_profile = user.profiles.create!(name: "Grandchild Profile")
    child.profiles << child_profile
    grandchild.profiles << grandchild_profile
    GroupGroup.create!(parent_group: parent, child_group: child,
                       inclusion_mode: "all", include_direct_profiles: false)
    GroupGroup.create!(parent_group: child, child_group: grandchild, inclusion_mode: "all")

    assert_not_includes parent.all_profiles, child_profile,
      "Child's own profiles should be excluded when include_direct_profiles is false"
    assert_includes parent.all_profiles, grandchild_profile,
      "Grandchild's profiles should still be visible (include_direct_profiles only affects the direct child)"
  end

  # -- InclusionOverride-driven traversal --
  #
  # An InclusionOverride lives on a specific edge (GroupGroup) and targets a
  # group deeper in the subtree. When traversal passes through that edge, the
  # override's settings replace the target group's own edge settings — but only
  # for that context. Viewing the target group directly, or through a different
  # ancestor edge, is unaffected.

  test "override changes inclusion_mode all→none: stops recursion for deep group in that context" do
    # root →(all)→ mid →(all)→ deep →(all)→ leaf
    # Override on root→mid edge targeting deep with inclusion_mode "none"
    # → deep appears from root, but leaf does not (recursion stopped)
    # → viewing mid directly still shows both deep and leaf
    user = users(:one)
    root = user.groups.create!(name: "Root")
    mid  = user.groups.create!(name: "Mid")
    deep = user.groups.create!(name: "Deep")
    leaf = user.groups.create!(name: "Leaf")
    root_mid  = GroupGroup.create!(parent_group: root, child_group: mid,  inclusion_mode: "all")
    GroupGroup.create!(parent_group: mid,  child_group: deep, inclusion_mode: "all")
    GroupGroup.create!(parent_group: deep, child_group: leaf, inclusion_mode: "all")

    # Without override, root sees all three descendants
    assert_equal %w[Deep Leaf Mid], root.descendant_sections.map(&:name).sort

    # Add an override on root→mid targeting deep: change to "none"
    InclusionOverride.create!(group_group: root_mid, target_group: deep, inclusion_mode: "none")

    root_sections = root.descendant_sections.map(&:name)
    assert_includes     root_sections, "Mid",  "Mid should still appear"
    assert_includes     root_sections, "Deep", "Deep should appear (the override targets it, not hides it)"
    assert_not_includes root_sections, "Leaf",
      "Leaf must be hidden — override stops recursion at Deep when traversing via root→mid"

    # Viewing mid directly still sees both deep and leaf (override is edge-contextual)
    mid_sections = mid.descendant_sections.map(&:name)
    assert_includes mid_sections, "Deep"
    assert_includes mid_sections, "Leaf"
  end

  test "override changes inclusion_mode none→all: enables recursion into previously-stopped group" do
    # root →(all)→ mid →(none)→ deep →(all)→ leaf
    # Without override: deep appears from root as overlapping; leaf invisible
    # Override on root→mid edge targeting deep with inclusion_mode "all"
    # → deep now recursed into; leaf becomes visible
    user = users(:one)
    root = user.groups.create!(name: "Root")
    mid  = user.groups.create!(name: "Mid")
    deep = user.groups.create!(name: "Deep")
    leaf = user.groups.create!(name: "Leaf")
    root_mid = GroupGroup.create!(parent_group: root, child_group: mid,  inclusion_mode: "all")
    GroupGroup.create!(parent_group: mid,  child_group: deep, inclusion_mode: "none")
    GroupGroup.create!(parent_group: deep, child_group: leaf, inclusion_mode: "all")

    # Without override, leaf is invisible from root
    assert_not_includes root.descendant_sections.map(&:name), "Leaf"

    # Add an override on root→mid targeting deep: change to "all"
    InclusionOverride.create!(group_group: root_mid, target_group: deep, inclusion_mode: "all")

    root_sections = root.descendant_sections.map(&:name)
    assert_includes root_sections, "Deep"
    assert_includes root_sections, "Leaf",
      "Leaf should now be visible — override opens up recursion through Deep in this context"

    # mid still sees deep as none (no override active for mid's own traversal)
    mid_tree = mid.descendant_tree
    deep_node = mid_tree.find { |n| n[:group].name == "Deep" }
    assert deep_node[:overlapping], "Deep should still be overlapping when viewed from mid directly"
  end

  test "override suppresses direct profiles of a deep group (include_direct_profiles false)" do
    # root →(all)→ mid →(all, include_direct_profiles: true)→ deep
    # deep has a direct profile (target_profile)
    # Override on root→mid edge targeting deep: include_direct_profiles false
    # → target_profile invisible from root, but visible from mid
    user = users(:one)
    root = user.groups.create!(name: "Root")
    mid  = user.groups.create!(name: "Mid")
    deep = user.groups.create!(name: "Deep")
    target_profile = user.profiles.create!(name: "Target Profile")
    deep.profiles << target_profile
    root_mid = GroupGroup.create!(parent_group: root, child_group: mid, inclusion_mode: "all")
    GroupGroup.create!(parent_group: mid, child_group: deep, inclusion_mode: "all",
                       include_direct_profiles: true)

    # Without override, root sees the profile
    assert_includes root.all_profiles, target_profile

    # Add override: suppress direct profiles of deep in root→mid context
    InclusionOverride.create!(group_group: root_mid, target_group: deep,
                              inclusion_mode: "all", include_direct_profiles: false)

    assert_not_includes root.all_profiles, target_profile,
      "Target profile should be hidden from root via the include_direct_profiles override"

    # mid's own view is unaffected
    assert_includes mid.all_profiles, target_profile,
      "Target profile should still appear when viewing mid directly"
  end

  test "override on descendant_tree suppresses profiles and is reflected in :profiles key" do
    user = users(:one)
    root = user.groups.create!(name: "Root")
    mid  = user.groups.create!(name: "Mid")
    deep = user.groups.create!(name: "Deep")
    deep_profile = user.profiles.create!(name: "Deep Profile")
    deep.profiles << deep_profile
    root_mid = GroupGroup.create!(parent_group: root, child_group: mid, inclusion_mode: "all")
    GroupGroup.create!(parent_group: mid, child_group: deep, inclusion_mode: "all")

    # Without override: deep_profile appears in deep's tree node
    tree = root.descendant_tree
    mid_node  = tree.find { |n| n[:group].name == "Mid" }
    deep_node = mid_node[:children].find { |n| n[:group].name == "Deep" }
    assert_includes deep_node[:profiles].map { |e| e[:profile] }, deep_profile

    # Add override: suppress deep's direct profiles
    InclusionOverride.create!(group_group: root_mid, target_group: deep,
                              inclusion_mode: "all", include_direct_profiles: false)

    tree = root.descendant_tree
    mid_node  = tree.find { |n| n[:group].name == "Mid" }
    deep_node = mid_node[:children].find { |n| n[:group].name == "Deep" }
    assert_empty deep_node[:profiles],
      "Deep's :profiles key must be empty after applying the include_direct_profiles override"
  end

  test "override changes inclusion_mode and descendant_tree marks node correctly" do
    # After a none→all override, the node should no longer be marked :overlapping
    user = users(:one)
    root = user.groups.create!(name: "Root")
    mid  = user.groups.create!(name: "Mid")
    deep = user.groups.create!(name: "Deep")
    root_mid = GroupGroup.create!(parent_group: root, child_group: mid, inclusion_mode: "all")
    GroupGroup.create!(parent_group: mid, child_group: deep, inclusion_mode: "none")

    # Without override: deep is overlapping from root
    tree = root.descendant_tree
    mid_node  = tree.find { |n| n[:group].name == "Mid" }
    deep_node = mid_node[:children].find { |n| n[:group].name == "Deep" }
    assert deep_node[:overlapping], "Deep should be overlapping before the override is applied"

    # Override: change deep's mode to "all" when traversed via root→mid
    InclusionOverride.create!(group_group: root_mid, target_group: deep, inclusion_mode: "all")

    tree = root.descendant_tree
    mid_node  = tree.find { |n| n[:group].name == "Mid" }
    deep_node = mid_node[:children].find { |n| n[:group].name == "Deep" }
    assert_not deep_node[:overlapping],
      "Deep should no longer be marked :overlapping when the override changes its mode to 'all'"
  end

  test "override is edge-contextual: only affects traversal through its specific ancestor edge" do
    # group_a →(all)→ mid →(all)→ deep →(all)→ leaf
    # group_b →(all)→ mid  (same mid group, same mid→deep edge)
    # Override on group_a→mid edge, targeting deep with mode "none"
    # → public page for group_a: deep appears as overlapping, leaf invisible, deep's profiles hidden
    # → public page for group_b: deep's full subtree is visible, profiles intact
    # The difference is which group's page is being rendered, not who is logged in.
    user = users(:one)
    group_a = user.groups.create!(name: "Group A")
    group_b = user.groups.create!(name: "Group B")
    mid  = user.groups.create!(name: "Mid")
    deep = user.groups.create!(name: "Deep")
    leaf = user.groups.create!(name: "Leaf")
    deep_profile = user.profiles.create!(name: "Deep Profile")
    deep.profiles << deep_profile

    ga_mid = GroupGroup.create!(parent_group: group_a, child_group: mid, inclusion_mode: "all")
    GroupGroup.create!(parent_group: group_b, child_group: mid, inclusion_mode: "all")
    GroupGroup.create!(parent_group: mid,     child_group: deep, inclusion_mode: "all")
    GroupGroup.create!(parent_group: deep,    child_group: leaf, inclusion_mode: "all")

    # Override on group_a→mid edge targeting deep: stop recursion and hide its direct profiles
    InclusionOverride.create!(group_group: ga_mid, target_group: deep,
                              inclusion_mode: "none", include_direct_profiles: false)

    # group_a's public page: mid and deep appear, leaf does not; deep's profiles are hidden
    ga_sections = group_a.descendant_sections.map(&:name)
    assert_includes     ga_sections, "Mid",  "Mid should appear on group_a's page"
    assert_includes     ga_sections, "Deep", "Deep should appear on group_a's page (override targets it, not hides it)"
    assert_not_includes ga_sections, "Leaf",
      "Leaf must be hidden on group_a's page — override stops recursion at deep"
    assert_not_includes group_a.all_profiles, deep_profile,
      "Deep's direct profiles must be hidden on group_a's page — include_direct_profiles override"

    # group_b's public page: full tree is visible (different ancestor edge, no override loaded)
    gb_sections = group_b.descendant_sections.map(&:name)
    assert_includes gb_sections, "Deep"
    assert_includes gb_sections, "Leaf",
      "Leaf should be visible on group_b's page — override on group_a→mid does not apply here"
    assert_includes group_b.all_profiles, deep_profile,
      "Deep Profile should be visible on group_b's page"
  end

  # -- editor_tree hidden_from_public flag -----------------------------------

  test "editor_tree marks direct children as not hidden" do
    alpha = groups(:alpha_clan)
    tree = alpha.editor_tree
    spectrum_node = tree.find { |n| n[:group] == groups(:spectrum) }

    assert_not spectrum_node[:hidden_from_public],
      "Direct child Spectrum should not be hidden from public"
  end

  test "editor_tree marks sub-groups as hidden when parent mode is none" do
    # Set Spectrum's edge in Alpha Clan to "none" (overlapping)
    gg = group_groups(:spectrum_in_alpha)
    gg.update!(inclusion_mode: "none")

    alpha = groups(:alpha_clan)
    tree = alpha.editor_tree
    spectrum_node = tree.find { |n| n[:group] == groups(:spectrum) }

    # Spectrum itself is a direct child → not hidden
    assert_not spectrum_node[:hidden_from_public],
      "Direct child Spectrum should not be hidden even with mode none"

    # Prism Circle is a child of Spectrum, but Spectrum has mode none → hidden
    prism_node = spectrum_node[:children].find { |n| n[:group] == groups(:prism_circle) }
    assert prism_node[:hidden_from_public],
      "Prism Circle should be hidden when parent Spectrum has mode none"

    # Rogue Pack is a grandchild of Spectrum → also hidden (ancestor hidden)
    rogue_node = prism_node[:children].find { |n| n[:group] == groups(:rogue_pack) }
    assert rogue_node[:hidden_from_public],
      "Rogue Pack should be hidden when ancestor is hidden"
  end

  test "editor_tree marks unselected sub-groups as hidden with selected mode" do
    # Castle Clan has Flux with mode "selected" including only Echo Shard
    castle = groups(:castle_clan)
    tree = castle.editor_tree
    flux_node = tree.find { |n| n[:group] == groups(:flux) }

    echo_node = flux_node[:children].find { |n| n[:group] == groups(:echo_shard) }
    static_node = flux_node[:children].find { |n| n[:group] == groups(:static_burst) }

    assert_not echo_node[:hidden_from_public],
      "Echo Shard should not be hidden — it is in the selected list"
    assert static_node[:hidden_from_public],
      "Static Burst should be hidden — it is not in the selected list"
  end

  test "editor_tree propagates hidden status to deep descendants" do
    # Castle Clan → Flux (selected, only Echo Shard) → Static Burst (hidden) → any children
    castle = groups(:castle_clan)

    # Add a child to Static Burst so we can test deep propagation
    user = users(:three)
    deep_child = user.groups.create!(name: "Deep Child")
    GroupGroup.create!(parent_group: groups(:static_burst), child_group: deep_child, inclusion_mode: "all")

    tree = castle.editor_tree
    flux_node = tree.find { |n| n[:group] == groups(:flux) }
    static_node = flux_node[:children].find { |n| n[:group] == groups(:static_burst) }
    deep_node = static_node[:children].find { |n| n[:group] == deep_child }

    assert static_node[:hidden_from_public], "Static Burst should be hidden"
    assert deep_node[:hidden_from_public],
      "Deep Child should be hidden because its ancestor Static Burst is hidden"
  end

  test "editor_tree marks nodes hidden when override sets mode to none" do
    alpha = groups(:alpha_clan)

    # Update the existing fixture override to "none" mode
    override = inclusion_overrides(:rogue_pack_excluded_from_alpha)
    override.update!(inclusion_mode: "none", included_subgroup_ids: [])

    tree = alpha.editor_tree
    spectrum_node = tree.find { |n| n[:group] == groups(:spectrum) }
    prism_node = spectrum_node[:children].find { |n| n[:group] == groups(:prism_circle) }
    rogue_node = prism_node[:children].find { |n| n[:group] == groups(:rogue_pack) }

    # Prism Circle itself is not hidden (mode "none" = overlapping, still visible)
    assert_not prism_node[:hidden_from_public],
      "Prism Circle should not be hidden — it appears as overlapping"

    # Rogue Pack is hidden because Prism Circle has mode none
    assert rogue_node[:hidden_from_public],
      "Rogue Pack should be hidden — Prism Circle's override sets mode to none"
  end

  test "editor_tree marks nodes hidden when override uses selected and excludes them" do
    # The fixture already has this exact setup:
    # spectrum_in_alpha edge with override on prism_circle:
    #   inclusion_mode: "selected", included_subgroup_ids: []
    alpha = groups(:alpha_clan)

    tree = alpha.editor_tree
    spectrum_node = tree.find { |n| n[:group] == groups(:spectrum) }
    prism_node = spectrum_node[:children].find { |n| n[:group] == groups(:prism_circle) }
    rogue_node = prism_node[:children].find { |n| n[:group] == groups(:rogue_pack) }

    assert_not prism_node[:hidden_from_public],
      "Prism Circle should not be hidden"
    assert rogue_node[:hidden_from_public],
      "Rogue Pack should be hidden — override selects no sub-groups"
  end
end
