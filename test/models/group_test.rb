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
end
