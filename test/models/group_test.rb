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

  test "descendant_sections: selected sub-group with all sub-edge appears but deeper children are limited by CTE depth" do
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
    # b →(all)→ b_child  — one level deeper than the CTE pre-loads for selected paths
    GroupGroup.create!(parent_group: b, child_group: b_child, inclusion_mode: "all")

    names = root.descendant_sections.map(&:name)
    assert_includes names, "Alpha", "Alpha should appear"
    assert_includes names, "Beta",  "Beta (all sub-edge, in selected list) should appear"
    # BetaChild sits one level below the effective CTE pre-load boundary for
    # selected paths, so it is not present in groups_by_id and must not appear.
    assert_not_includes names, "BetaChild",
      "BetaChild is beyond the CTE pre-load depth for selected paths and must not appear"
  end
end
