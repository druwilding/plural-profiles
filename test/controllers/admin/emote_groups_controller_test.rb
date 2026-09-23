require "test_helper"

class Admin::EmoteGroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    @hearts = emote_groups(:hearts)
  end

  test "non-admins are redirected" do
    sign_in_as users(:two)
    post admin_emote_groups_path, params: { emote_group: { name: "Other", plain_text: "★" } }

    assert_redirected_to root_path
    assert_not EmoteGroup.exists?(name: "Other")
  end

  test "index lists groups in order with their emote counts" do
    EmoteGroup.create!(name: "Other", position: 1, plain_text: "★")
    sign_in_as @admin
    get admin_emote_groups_path

    assert_response :success
    assert_equal [ "Hearts", "Other" ], css_select(".emote-groups__group input[name='emote_group[name]']").map { |input| input["value"] }
    assert_select ".emote-groups__count", text: "50 emotes"
    assert_select ".emote-groups__count", text: "0 emotes"
  end

  test "index requires an admin" do
    sign_in_as users(:two)
    get admin_emote_groups_path
    assert_redirected_to root_path
  end

  test "create adds a group at the end" do
    sign_in_as @admin
    post admin_emote_groups_path, params: { emote_group: { name: "Other", plain_text: "★" } }

    assert_redirected_to admin_emote_groups_path
    group = EmoteGroup.find_by!(name: "Other")
    assert_equal 1, group.position
    assert_nil group.owner
  end

  test "create reports validation errors" do
    sign_in_as @admin
    post admin_emote_groups_path, params: { emote_group: { name: "Other", plain_text: "" } }

    assert_redirected_to admin_emote_groups_path
    assert_match "Plain text can't be blank", flash[:alert]
  end

  test "update renames a group and changes its symbol" do
    sign_in_as @admin
    patch admin_emote_group_path(@hearts), params: { emote_group: { name: "Love", plain_text: "❤" } }

    @hearts.reload
    assert_equal "Love", @hearts.name
    assert_equal "❤", @hearts.plain_text
  end

  test "move swaps a group with its neighbour and renumbers positions" do
    other = EmoteGroup.create!(name: "Other", position: 7, plain_text: "★")
    sign_in_as @admin
    patch move_admin_emote_group_path(other, direction: "up")

    assert_equal [ other, @hearts ], EmoteGroup.site_wide.ordered.to_a
    assert_equal [ 0, 1 ], EmoteGroup.site_wide.ordered.pluck(:position)
  end

  test "moving the first group up does nothing" do
    sign_in_as @admin
    patch move_admin_emote_group_path(@hearts, direction: "up")

    assert_redirected_to admin_emote_groups_path
    assert_equal 0, @hearts.reload.position
  end

  test "only an empty group can be deleted" do
    sign_in_as @admin
    delete admin_emote_group_path(@hearts)
    assert EmoteGroup.exists?(@hearts.id)
    assert_match "Only an empty group", flash[:alert]

    other = EmoteGroup.create!(name: "Other", position: 1, plain_text: "★")
    delete admin_emote_group_path(other)
    assert_not EmoteGroup.exists?(other.id)
  end
end
