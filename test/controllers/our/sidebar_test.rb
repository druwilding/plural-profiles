require "test_helper"

# Tests that the OurSidebar concern correctly populates the sidebar on every
# authenticated controller action, and stays silent for unauthenticated ones.
class Our::SidebarTest < ActionDispatch::IntegrationTest
  # ── Authenticated — correct content rendered ──────────────────────────────

  test "sidebar renders top-level group for authenticated user" do
    sign_in_as users(:one)
    get our_groups_path
    assert_response :success
    # "Everyone" is the sole top-level group for user :one
    assert_match "Everyone", response.body
  end

  test "sidebar renders nested child group for authenticated user" do
    sign_in_as users(:one)
    get our_groups_path
    assert_response :success
    # "Friends" is a child of "Everyone"
    assert_match "Friends", response.body
  end

  test "sidebar renders all profiles section for authenticated user" do
    sign_in_as users(:one)
    get our_groups_path
    assert_response :success
    # All profiles for the account appear in the Profiles section
    assert_match "Profiles", response.body
    assert_match "Bob", response.body
    assert_match "Alice", response.body
  end

  test "sidebar does not render another user's groups" do
    sign_in_as users(:one)
    get our_groups_path
    assert_response :success
    # "Family" belongs to user :two and must not appear in user :one's sidebar
    assert_no_match "Family", response.body
  end

  test "sidebar is populated on profile pages as well as group pages" do
    sign_in_as users(:one)
    get our_profile_path(profiles(:alice))
    assert_response :success
    assert_match "Everyone", response.body
    assert_match "Friends", response.body
  end

  # ── Unauthenticated — no sidebar, redirected ─────────────────────────────

  test "unauthenticated request to groups index is redirected" do
    get our_groups_path
    assert_redirected_to new_session_path
  end

  test "unauthenticated response contains no sidebar tree markup" do
    get our_groups_path
    follow_redirect!
    # The login page must not render the authenticated sidebar
    assert_no_match "sidebar-tree", response.body
  end
end
