require "test_helper"

class GroupGroupTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @everyone = groups(:everyone)
    @friends = groups(:friends)
  end

  test "valid group group is saved" do
    assert group_groups(:friends_in_everyone).valid?
  end

  test "prevents duplicate pair" do
    duplicate = GroupGroup.new(parent_group: @everyone, child_group: @friends)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:child_group_id], "has already been taken"
  end

  test "prevents self-referencing" do
    link = GroupGroup.new(parent_group: @friends, child_group: @friends)
    assert_not link.valid?
    assert_includes link.errors[:child_group], "cannot be the same as the parent group"
  end

  test "prevents cross-user linking" do
    family = groups(:family) # belongs to user two
    link = GroupGroup.new(parent_group: @friends, child_group: family)
    assert_not link.valid?
    assert_includes link.errors[:child_group], "must belong to the same user"
  end

  test "prevents circular reference A → B → A" do
    # everyone → friends already exists, try friends → everyone
    link = GroupGroup.new(parent_group: @friends, child_group: @everyone)
    assert_not link.valid?
    assert_includes link.errors[:child_group], "would create a circular reference"
  end

  test "prevents deeper circular reference A → B → C → A" do
    # Create a chain: everyone → friends → new_group, then try new_group → everyone
    new_group = @user.groups.create!(name: "Coworkers")
    GroupGroup.create!(parent_group: @friends, child_group: new_group)

    link = GroupGroup.new(parent_group: new_group, child_group: @everyone)
    assert_not link.valid?
    assert_includes link.errors[:child_group], "would create a circular reference"
  end

  test "allows non-circular chains" do
    new_group = @user.groups.create!(name: "Coworkers")
    link = GroupGroup.new(parent_group: @friends, child_group: new_group)
    assert link.valid?
  end

  test "parent_group association" do
    gg = group_groups(:friends_in_everyone)
    assert_equal @everyone, gg.parent_group
  end

  test "child_group association" do
    gg = group_groups(:friends_in_everyone)
    assert_equal @friends, gg.child_group
  end

  test "destroying parent group cascades to group_groups" do
    assert_difference("GroupGroup.count", -1) do
      @everyone.destroy
    end
  end

  test "destroying child group cascades to group_groups" do
    assert_difference("GroupGroup.count", -1) do
      @friends.destroy
    end
  end

  # -- Relationship type --

  test "defaults to nested relationship type" do
    new_group = @user.groups.create!(name: "Coworkers")
    link = GroupGroup.create!(parent_group: @everyone, child_group: new_group)
    assert_equal "nested", link.relationship_type
    assert link.nested?
    assert_not link.overlapping?
  end

  test "can be set to overlapping" do
    new_group = @user.groups.create!(name: "Coworkers")
    link = GroupGroup.create!(parent_group: @everyone, child_group: new_group, relationship_type: "overlapping")
    assert_equal "overlapping", link.relationship_type
    assert link.overlapping?
    assert_not link.nested?
  end

  test "rejects invalid relationship type" do
    new_group = @user.groups.create!(name: "Coworkers")
    link = GroupGroup.new(parent_group: @everyone, child_group: new_group, relationship_type: "invalid")
    assert_not link.valid?
    assert_includes link.errors[:relationship_type], "is not included in the list"
  end

  test "nested scope returns only nested links" do
    new_group = @user.groups.create!(name: "Coworkers")
    GroupGroup.create!(parent_group: @everyone, child_group: new_group, relationship_type: "overlapping")
    nested = @everyone.child_links.nested
    assert nested.all?(&:nested?)
  end

  test "overlapping scope returns only overlapping links" do
    new_group = @user.groups.create!(name: "Coworkers")
    GroupGroup.create!(parent_group: @everyone, child_group: new_group, relationship_type: "overlapping")
    overlapping = @everyone.child_links.overlapping
    assert overlapping.all?(&:overlapping?)
  end
end
