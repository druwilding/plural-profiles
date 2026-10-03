require "test_helper"

class PositionedTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "positioned items come first, in position order, then the rest alphabetically" do
    zed    = @user.profiles.create!(name: "Zed", position: 0)
    yara   = @user.profiles.create!(name: "Yara", position: 1)
    amber  = @user.profiles.create!(name: "Amber")
    basil  = @user.profiles.create!(name: "Basil")

    ordered = @user.profiles.where(id: [ amber, basil, yara, zed ]).order_by_position_then_name
    assert_equal [ zed, yara, amber, basil ], ordered.to_a
  end

  test "a list with no positions is alphabetical" do
    beta  = @user.groups.create!(name: "Beta")
    alpha = @user.groups.create!(name: "alpha")

    ordered = @user.groups.where(id: [ beta, alpha ]).order_by_position_then_name
    assert_equal [ alpha, beta ], ordered.to_a
  end

  test "orders by a link table's position when given its name" do
    group = @user.groups.create!(name: "Partners")
    alex  = @user.profiles.create!(name: "Alex", position: 0)
    sam   = @user.profiles.create!(name: "Sam", position: 1)
    GroupProfile.create!(group: group, profile: alex, position: 1)
    GroupProfile.create!(group: group, profile: sam, position: 0)

    assert_equal [ sam, alex ], profiles_in(group)
  end

  test "the same profile can sit in different places in different groups" do
    partners = @user.groups.create!(name: "Partners")
    littles  = @user.groups.create!(name: "Littles")
    alex     = @user.profiles.create!(name: "Alex")
    sam      = @user.profiles.create!(name: "Sam")
    GroupProfile.create!(group: partners, profile: sam, position: 0)
    GroupProfile.create!(group: partners, profile: alex, position: 1)
    GroupProfile.create!(group: littles, profile: alex, position: 0)
    GroupProfile.create!(group: littles, profile: sam, position: 1)

    assert_equal [ sam, alex ], profiles_in(partners)
    assert_equal [ alex, sam ], profiles_in(littles)
  end

  test "child groups order by the parent link's position" do
    parent = @user.groups.create!(name: "Parent")
    first  = @user.groups.create!(name: "Zulu", position: 5)
    second = @user.groups.create!(name: "Alpha", position: 0)
    GroupGroup.create!(parent_group: parent, child_group: first, position: 0)
    GroupGroup.create!(parent_group: parent, child_group: second, position: 1)

    assert_equal [ first, second ], Group.joins(:parent_links).where(group_groups: { parent_group_id: parent.id }).order_by_position_then_name(:group_groups).to_a
  end

  test "position_sort_key matches the SQL ordering" do
    records = [
      @user.profiles.create!(name: "Mira"),
      @user.profiles.create!(name: "zane", position: 2),
      @user.profiles.create!(name: "Abe", labels: [ "work" ]),
      @user.profiles.create!(name: "Abe"),
      @user.profiles.create!(name: "Quinn", position: 0)
    ]

    sql_order = @user.profiles.where(id: records).order_by_position_then_name.to_a
    assert_equal sql_order, records.sort_by(&:position_sort_key)
  end

  test "position_sort_key accepts a link's position in place of the record's own" do
    alex = @user.profiles.create!(name: "Alex", position: 0)
    sam  = @user.profiles.create!(name: "Sam", position: 1)

    link_positions = { alex.id => 1, sam.id => 0 }
    assert_equal [ sam, alex ], [ alex, sam ].sort_by { |p| p.position_sort_key(link_positions[p.id]) }
  end

  private

  def profiles_in(group)
    Profile.joins(:group_profiles).where(group_profiles: { group_id: group.id }).order_by_position_then_name(:group_profiles).to_a
  end
end
