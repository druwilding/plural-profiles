require "test_helper"

class GroupGroupTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @everyone = groups(:everyone)
    @friends = groups(:friends)
  end

  test "valid link between two groups of the same user" do
    new_group = @user.groups.create!(name: "New Group")
    link = GroupGroup.new(parent_group: @everyone, child_group: new_group)
    assert link.valid?
  end

  test "rejects duplicate parent-child pair" do
    # everyone -> friends already exists
    link = GroupGroup.new(parent_group: @everyone, child_group: @friends)
    assert_not link.valid?
    assert_includes link.errors[:child_group_id], "has already been taken"
  end

  test "rejects self-referencing link" do
    link = GroupGroup.new(parent_group: @friends, child_group: @friends)
    assert_not link.valid?
    assert_includes link.errors[:child_group], "cannot be the same as the parent group"
  end

  test "rejects cross-user link" do
    family = groups(:family)  # belongs to user :two
    link = GroupGroup.new(parent_group: @everyone, child_group: family)
    assert_not link.valid?
    assert_includes link.errors[:child_group], "must belong to the same user"
  end

  test "rejects circular reference" do
    user = users(:one)
    a = user.groups.create!(name: "A")
    b = user.groups.create!(name: "B")
    c = user.groups.create!(name: "C")

    GroupGroup.create!(parent_group: a, child_group: b)
    GroupGroup.create!(parent_group: b, child_group: c)

    # c -> a would create a cycle
    link = GroupGroup.new(parent_group: c, child_group: a)
    assert_not link.valid?
    assert_includes link.errors[:child_group], "would create a circular reference"
  end

  test "belongs to parent and child groups" do
    link = GroupGroup.find_by(parent_group: @everyone, child_group: @friends)
    assert_equal @everyone, link.parent_group
    assert_equal @friends, link.child_group
  end

  test "destroying link does not destroy groups" do
    new_group = @user.groups.create!(name: "Temp Group")
    link = GroupGroup.create!(parent_group: @everyone, child_group: new_group)
    link.destroy!

    assert Group.exists?(new_group.id)
    assert Group.exists?(@everyone.id)
  end

  test "cascade delete when parent group is destroyed" do
    new_group = @user.groups.create!(name: "Temp Group")
    GroupGroup.create!(parent_group: @everyone, child_group: new_group)

    assert GroupGroup.exists?(parent_group: @everyone, child_group: new_group)
    new_group.destroy!
    assert_not GroupGroup.exists?(parent_group: @everyone, child_group: new_group)
  end
end
