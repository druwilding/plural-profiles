require "test_helper"

class ListOrderTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email_address: "list_order@example.com",
      password: "Plur4l!Pr0files#2026",
      password_confirmation: "Plur4l!Pr0files#2026"
    )
    @household = @user.groups.create!(name: "Household")
    @alpha     = @user.groups.create!(name: "Alpha")
    @zeta      = @user.groups.create!(name: "Zeta")
    @household.child_links.create!(child_group: @alpha)
    @household.child_links.create!(child_group: @zeta)

    @ash  = @user.profiles.create!(name: "Ash")
    @wren = @user.profiles.create!(name: "Wren")
    @household.group_profiles.create!(profile: @ash)
    @household.group_profiles.create!(profile: @wren)
  end

  test "saves the profiles inside a group" do
    ListOrder.new(user: @user, list: "group_profiles", group: @household).save!([ @wren.uuid, @ash.uuid ])
    assert_equal [ @wren, @ash ], @household.ordered_profiles.to_a
  end

  test "saving inside one group leaves the profile's place in other groups alone" do
    other = @user.groups.create!(name: "Other")
    other.group_profiles.create!(profile: @ash, position: 0)
    other.group_profiles.create!(profile: @wren, position: 1)

    ListOrder.new(user: @user, list: "group_profiles", group: @household).save!([ @wren.uuid, @ash.uuid ])
    assert_equal [ @ash, @wren ], other.ordered_profiles.to_a
    assert_nil @ash.reload.position
  end

  test "saves the child groups inside a group" do
    ListOrder.new(user: @user, list: "group_groups", group: @household).save!([ @zeta.uuid, @alpha.uuid ])
    assert_equal [ @zeta, @alpha ], @household.ordered_child_groups.to_a
  end

  test "saves the account-wide profile order" do
    ListOrder.new(user: @user, list: "profiles").save!([ @wren.uuid, @ash.uuid ])
    assert_equal [ 1, 0 ], [ @ash.reload.position, @wren.reload.position ]
  end

  test "saves the top-level group order" do
    other = @user.groups.create!(name: "Another")
    ListOrder.new(user: @user, list: "groups").save!([ other.uuid, @household.uuid ])
    assert_equal [ 0, 1 ], [ other.reload.position, @household.reload.position ]
  end

  test "the top-level group order doesn't accept nested groups" do
    assert_raises(ListOrder::StaleList) do
      ListOrder.new(user: @user, list: "groups").save!([ @household.uuid, @alpha.uuid ])
    end
  end

  test "saving the top-level order clears positions left on groups that are now nested" do
    @alpha.update!(position: 0)
    ListOrder.new(user: @user, list: "groups").save!([ @household.uuid ])
    assert_nil @alpha.reload.position
  end

  test "a list with a missing member is stale and writes nothing" do
    assert_raises(ListOrder::StaleList) do
      ListOrder.new(user: @user, list: "group_profiles", group: @household).save!([ @wren.uuid ])
    end
    assert_equal [ nil, nil ], @household.group_profiles.pluck(:position)
  end

  test "a list with an extra or duplicated member is stale" do
    stranger = @user.profiles.create!(name: "Stranger")
    order = ListOrder.new(user: @user, list: "group_profiles", group: @household)

    assert_raises(ListOrder::StaleList) { order.save!([ @wren.uuid, @ash.uuid, stranger.uuid ]) }
    assert_raises(ListOrder::StaleList) { order.save!([ @wren.uuid, @wren.uuid ]) }
  end

  test "another user's profile can't be slipped into the list" do
    assert_raises(ListOrder::StaleList) do
      ListOrder.new(user: @user, list: "profiles").save!([ @wren.uuid, profiles(:alice).uuid ])
    end
  end

  test "reset clears the list's positions" do
    order = ListOrder.new(user: @user, list: "group_profiles", group: @household)
    order.save!([ @wren.uuid, @ash.uuid ])
    order.reset!

    assert_equal [ nil, nil ], @household.group_profiles.pluck(:position)
    assert_equal [ @ash, @wren ], @household.ordered_profiles.to_a
  end

  test "rejects unknown lists, missing groups and other users' groups" do
    assert_raises(ListOrder::InvalidList) { ListOrder.new(user: @user, list: "themes") }
    assert_raises(ListOrder::InvalidList) { ListOrder.new(user: @user, list: "group_profiles") }
    assert_raises(ListOrder::InvalidList) { ListOrder.new(user: @user, list: "group_profiles", group: groups(:friends)) }
  end
end
