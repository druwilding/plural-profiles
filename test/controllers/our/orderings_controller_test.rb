require "test_helper"

class Our::OrderingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @group = groups(:everyone)
    sign_in_as @user
  end

  test "saves the profiles inside a group" do
    @group.group_profiles.create!(profile: profiles(:bob))
    uuids = @group.ordered_profiles.map(&:uuid).reverse
    patch our_ordering_path, params: { list: "group_profiles", group: @group.uuid, ids: uuids }, as: :json

    assert_response :no_content
    assert_equal 2, uuids.size
    assert_equal uuids, @group.ordered_profiles.map(&:uuid)
  end

  test "saves the account-wide profile order" do
    uuids = @user.profiles.order_by_position_then_name.map(&:uuid).reverse
    patch our_ordering_path, params: { list: "profiles", ids: uuids }, as: :json

    assert_response :no_content
    assert_equal uuids, @user.profiles.order_by_position_then_name.map(&:uuid)
  end

  test "resets a list to alphabetical" do
    @user.profiles.update_all(position: 3)
    patch our_ordering_path, params: { list: "profiles", reset: "true" }, as: :json

    assert_response :no_content
    assert @user.profiles.all? { |profile| profile.position.nil? }
  end

  test "an out-of-date list is a conflict" do
    patch our_ordering_path, params: { list: "profiles", ids: [ profiles(:alice).uuid ] }, as: :json
    assert_response :conflict
  end

  test "ids that aren't a list are a conflict, not an error" do
    patch our_ordering_path, params: { list: "profiles", ids: { "0" => profiles(:alice).uuid } }, as: :json
    assert_response :conflict
  end

  test "another user's group is not found" do
    patch our_ordering_path, params: { list: "group_profiles", group: groups(:family).uuid, ids: [] }, as: :json
    assert_response :not_found
  end

  test "an unknown list is a bad request" do
    patch our_ordering_path, params: { list: "themes", ids: [] }, as: :json
    assert_response :bad_request
  end

  test "requires signing in" do
    sign_out
    patch our_ordering_path, params: { list: "profiles", ids: [] }, as: :json
    assert_response :redirect
  end
end
