require "test_helper"

class Admin::EmoteSetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    @hearts = emote_sets(:hearts)
  end

  test "non-admins are redirected" do
    sign_in_as users(:two)
    post admin_emote_sets_path, params: { emote_set: { name: "Other" } }

    assert_redirected_to root_path
    assert_not EmoteSet.exists?(name: "Other")
  end

  test "index lists sets in order with their emote counts" do
    EmoteSet.create!(name: "Other", position: 1)
    sign_in_as @admin
    get admin_emote_sets_path

    assert_response :success
    assert_equal [ "Hearts", "Other" ], css_select(".emote-sets__set input[name='emote_set[name]']").map { |input| input["value"] }
    assert_select ".emote-sets__count", text: "50 emotes"
    assert_select ".emote-sets__count", text: "0 emotes"
  end

  test "index requires an admin" do
    sign_in_as users(:two)
    get admin_emote_sets_path
    assert_redirected_to root_path
  end

  test "create adds a set at the end" do
    sign_in_as @admin
    post admin_emote_sets_path, params: { emote_set: { name: "Other" } }

    assert_redirected_to admin_emote_sets_path
    emote_set = EmoteSet.find_by!(name: "Other")
    assert_equal 1, emote_set.position
    assert_nil emote_set.owner
  end

  test "create reports validation errors" do
    sign_in_as @admin
    post admin_emote_sets_path, params: { emote_set: { name: "" } }

    assert_redirected_to admin_emote_sets_path
    assert_match "Name can't be blank", flash[:alert]
  end

  test "update renames a set" do
    sign_in_as @admin
    patch admin_emote_set_path(@hearts), params: { emote_set: { name: "Love" } }

    assert_equal "Love", @hearts.reload.name
  end

  test "move swaps a set with its neighbour and renumbers positions" do
    other = EmoteSet.create!(name: "Other", position: 7)
    sign_in_as @admin
    patch move_admin_emote_set_path(other, direction: "up")

    assert_equal [ other, @hearts ], EmoteSet.site_wide.ordered.to_a
    assert_equal [ 0, 1 ], EmoteSet.site_wide.ordered.pluck(:position)
  end

  test "moving the first set up does nothing" do
    sign_in_as @admin
    patch move_admin_emote_set_path(@hearts, direction: "up")

    assert_redirected_to admin_emote_sets_path
    assert_equal 0, @hearts.reload.position
  end

  test "only an empty set can be deleted" do
    sign_in_as @admin
    delete admin_emote_set_path(@hearts)
    assert EmoteSet.exists?(@hearts.id)
    assert_match "Only an empty set", flash[:alert]

    other = EmoteSet.create!(name: "Other", position: 1)
    delete admin_emote_set_path(other)
    assert_not EmoteSet.exists?(other.id)
  end
end
