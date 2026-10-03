require "test_helper"

# Every place that lists groups or profiles follows the custom order from
# Positioned. The tree is built so that alphabetical order and custom order
# disagree everywhere:
#
#   Another (top-level, account position 0)
#   Household (top-level, unpositioned)
#     Zeta team   (link position 0)
#       Bea       (link position 0)
#       Ash       (link position 1)
#     Alpha team  (link position 1)
#     Wren        (link position 0)
#     Ash         (link position 1)
#     Bea         (unpositioned)
class CustomOrderingTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email_address: "ordering@example.com",
      password: "Plur4l!Pr0files#2026",
      password_confirmation: "Plur4l!Pr0files#2026"
    )
    @another   = @user.groups.create!(name: "Another", position: 0)
    @household = @user.groups.create!(name: "Household")
    @alpha     = @user.groups.create!(name: "Alpha team")
    @zeta      = @user.groups.create!(name: "Zeta team")
    GroupGroup.create!(parent_group: @household, child_group: @zeta, position: 0)
    GroupGroup.create!(parent_group: @household, child_group: @alpha, position: 1)

    @ash  = @user.profiles.create!(name: "Ash", position: 2)
    @bea  = @user.profiles.create!(name: "Bea")
    @wren = @user.profiles.create!(name: "Wren", position: 0)
    GroupProfile.create!(group: @household, profile: @wren, position: 0)
    GroupProfile.create!(group: @household, profile: @ash, position: 1)
    GroupProfile.create!(group: @household, profile: @bea)
    GroupProfile.create!(group: @zeta, profile: @bea, position: 0)
    GroupProfile.create!(group: @zeta, profile: @ash, position: 1)
  end

  test "ordered_profiles and ordered_child_groups follow the group's own order" do
    assert_equal [ @wren, @ash, @bea ], @household.ordered_profiles.to_a
    assert_equal [ @bea, @ash ], @zeta.ordered_profiles.to_a
    assert_equal [ @zeta, @alpha ], @household.ordered_child_groups.to_a
  end

  test "ordered_profiles_from_preload matches ordered_profiles" do
    household = Group.includes(group_profiles: :profile).find(@household.id)
    assert_equal @household.ordered_profiles.to_a, household.ordered_profiles_from_preload
  end

  test "public root lists follow the custom order" do
    assert_equal [ @wren, @ash, @bea ], @household.visible_root_profiles.to_a
    assert_equal [ @zeta, @alpha ], @household.visible_direct_child_groups.to_a
  end

  test "public lists for a nested group follow that group's order" do
    path = [ @zeta.id ]
    assert_equal [ @bea, @ash ], @zeta.profiles_visible_at_path(path, root_group_id: @household.id).to_a
  end

  test "hidden profiles drop out without disturbing the order" do
    InclusionOverride.create!(group: @household, path: [], target_type: "Profile", target_id: @ash.id)
    assert_equal [ @wren, @bea ], @household.visible_root_profiles.to_a
  end

  test "descendant_tree orders child groups and their profiles" do
    tree = @household.descendant_tree
    assert_equal [ @zeta, @alpha ], tree.map { |node| node[:group] }
    assert_equal [ @bea, @ash ], tree.first[:profiles].map { |entry| entry[:profile] }
  end

  test "descendant_sections follows the custom order" do
    assert_equal [ @zeta, @alpha ], @household.descendant_sections
  end

  test "management lists follow the custom order" do
    tree = @household.management_tree
    assert_equal [ @zeta, @alpha ], tree.map { |node| node[:group] }
    assert_equal [ @bea, @ash ], tree.first[:profiles].map { |entry| entry[:profile] }
    assert_equal [ @wren, @ash, @bea ], @household.management_root_profiles.map { |entry| entry[:profile] }
  end

  test "duplication preview follows the custom order" do
    tree = @household.duplication_preview_tree(labels: [ "copy" ], resolutions: {})
    assert_equal [ @zeta, @alpha ], tree.map { |node| node[:group] }
    assert_equal [ @bea, @ash ], tree.first[:profiles].map { |entry| entry[:profile] }
  end

  test "sidebar_tree orders top-level groups, nested groups and profiles" do
    sidebar = @user.sidebar_tree
    assert_equal [ @another, @household ], sidebar[:trees].map { |node| node[:group] }

    household = sidebar[:trees].second
    assert_equal [ @zeta, @alpha ], household[:children].map { |node| node[:group] }
    assert_equal [ @wren, @ash, @bea ], household[:profiles].map { |entry| entry[:profile] }
    assert_equal [ @bea, @ash ], household[:children].first[:profiles].map { |entry| entry[:profile] }
  end

  test "sidebar_tree lists all profiles in the account-wide order" do
    assert_equal [ @wren, @ash, @bea ], @user.sidebar_tree[:all_profiles].to_a
  end

  test "ordering trees doesn't add queries per group" do
    sidebar_before = count_queries { @user.sidebar_tree[:trees].to_a }
    tree_before = count_queries { @household.descendant_tree }

    3.times do |i|
      group = @user.groups.create!(name: "Extra #{i}")
      GroupGroup.create!(parent_group: @zeta, child_group: group, position: i)
      GroupProfile.create!(group: group, profile: @ash, position: 0)
      GroupProfile.create!(group: group, profile: @bea, position: 1)
    end

    assert_equal sidebar_before, count_queries { @user.sidebar_tree[:trees].to_a }
    assert_equal tree_before, count_queries { @household.descendant_tree }
  end

  test "deep_duplicate keeps the order inside each group" do
    copy = @household.deep_duplicate(new_labels: [ "copy" ])

    assert_equal [ "Zeta team", "Alpha team" ], copy.ordered_child_groups.map(&:name)
    assert_equal [ "Wren", "Ash", "Bea" ], copy.ordered_profiles.map(&:name)
    zeta_copy = copy.ordered_child_groups.first
    assert_equal [ "Bea", "Ash" ], zeta_copy.ordered_profiles.map(&:name)
  end

  test "deep_duplicate puts copies at the end of the account-wide order" do
    copy = @household.deep_duplicate(new_labels: [ "copy" ])

    assert_nil copy.position
    assert copy.ordered_profiles.all? { |profile| profile.position.nil? }
  end

  private

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
