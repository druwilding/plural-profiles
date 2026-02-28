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

  test "prevents partial circular relationship" do
    # A->B (none)
    # B->C (all)
    # C->A is allowed (not a circular reference)
    a = @user.groups.create!(name: "A")
    b = @user.groups.create!(name: "B")
    c = @user.groups.create!(name: "C")
    GroupGroup.create!(parent_group: a, child_group: b, inclusion_mode: "none")
    GroupGroup.create!(parent_group: b, child_group: c, inclusion_mode: "all")

    link = GroupGroup.new(parent_group: c, child_group: a)
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

  test "defaults to all inclusion mode" do
    new_group = @user.groups.create!(name: "Coworkers")
    link = GroupGroup.create!(parent_group: @everyone, child_group: new_group)
    assert_equal "all", link.inclusion_mode
    assert link.all?
    assert_not link.none?
  end

  test "can be set to none" do
    new_group = @user.groups.create!(name: "Coworkers")
    link = GroupGroup.create!(parent_group: @everyone, child_group: new_group, inclusion_mode: "none")
    assert_equal "none", link.inclusion_mode
    assert link.none?
    assert_not link.all?
  end

  test "rejects invalid inclusion mode" do
    new_group = @user.groups.create!(name: "Coworkers")
    link = GroupGroup.new(parent_group: @everyone, child_group: new_group, inclusion_mode: "invalid")
    assert_not link.valid?
    assert_includes link.errors[:inclusion_mode], "is not included in the list"
  end

  test "all_mode scope returns only all-mode links" do
    new_group = @user.groups.create!(name: "Coworkers")
    GroupGroup.create!(parent_group: @everyone, child_group: new_group, inclusion_mode: "none")
    all = @everyone.child_links.all_mode
    assert all.all?(&:all?)
  end

  test "none_mode scope returns only none-mode links" do
    new_group = @user.groups.create!(name: "Coworkers")
    GroupGroup.create!(parent_group: @everyone, child_group: new_group, inclusion_mode: "none")
    none = @everyone.child_links.none_mode
    assert none.all?(&:none?)
  end
end
