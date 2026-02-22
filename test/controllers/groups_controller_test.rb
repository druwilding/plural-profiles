require "test_helper"

class GroupsControllerTest < ActionDispatch::IntegrationTest
  test "show displays public group by uuid" do
    group = groups(:friends)
    get group_path(uuid: group.uuid)
    assert_response :success
    assert_match "Friends", response.body
  end

  test "show lists group profiles" do
    group = groups(:friends)
    get group_path(uuid: group.uuid)
    assert_response :success
    assert_match "Alice", response.body
  end

  test "show works when logged in" do
    sign_in_as users(:one)
    group = groups(:friends)
    get group_path(uuid: group.uuid)
    assert_response :success
  end

  test "show returns 404 for unknown uuid" do
    get group_path(uuid: "nonexistent-uuid")
    assert_response :not_found
  end

  test "show displays sub-group names as headings" do
    everyone = groups(:everyone)
    get group_path(uuid: everyone.uuid)
    assert_response :success
    assert_match "Friends", response.body
  end

  test "show includes profiles from sub-groups inline" do
    everyone = groups(:everyone)
    get group_path(uuid: everyone.uuid)
    assert_response :success
    # Alice is in friends, which is a child of everyone
    assert_match "Alice", response.body
  end
end
