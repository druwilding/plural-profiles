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
    assert_includes group.errors[:avatar], "must be a PNG, JPEG, GIF, or WebP image"
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
    # Close Friends has Alice
    assert_equal [ "Alice" ], tree.first[:children].first[:profiles].map(&:name)
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
end
