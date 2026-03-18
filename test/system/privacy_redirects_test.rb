require "application_system_test_case"

# These tests simulate the real-world scenario where someone accidentally
# shares a private "/our/" URL. Recipients — whether logged out or logged
# in as a different user — must be gracefully redirected to the public
# page and must never see edit, delete or manage controls.

class PrivacyRedirectsTest < ApplicationSystemTestCase
  setup do
    @owner = users(:one)
    @stranger = users(:two)
    @profile = profiles(:alice)
    @group = groups(:friends)
  end

  # ── Logged-out visitor clicks a private profile URL ───────────────

  test "logged-out visitor on private profile URL is sent to sign in" do
    visit our_profile_path(@profile)

    assert_current_path new_session_path
  end

  # ── Logged-out visitor clicks a private group URL ─────────────────

  test "logged-out visitor on private group URL is sent to sign in" do
    visit our_group_path(@group)

    assert_current_path new_session_path
  end

  # ── Logged-out visitor on public UUID URLs ────────────────────────

  test "logged-out visitor on public profile UUID URL is sent to sign in" do
    visit profile_path(@profile.uuid)

    assert_current_path new_session_path
  end

  test "logged-out visitor on public group UUID URL is sent to sign in" do
    visit group_path(@group.uuid)

    assert_current_path new_session_path
  end

  # ── Logged-out visitor tries private index/new pages ──────────────

  test "logged-out visitor on profiles index is sent to sign in" do
    visit our_profiles_path

    assert_current_path new_session_path
  end

  test "logged-out visitor on groups index is sent to sign in" do
    visit our_groups_path

    assert_current_path new_session_path
  end

  test "logged-out visitor on new profile page is sent to sign in" do
    visit new_our_profile_path

    assert_current_path new_session_path
  end

  test "logged-out visitor on new group page is sent to sign in" do
    visit new_our_group_path

    assert_current_path new_session_path
  end

  # ── Wrong user clicks a private profile URL ──────────────────────

  test "wrong user on private profile URL sees public profile" do
    sign_in_via_browser(@stranger)

    visit our_profile_path(@profile)

    assert_current_path profile_path(@profile.uuid)
    assert_text "Alice"
    assert_text "she/her"

    assert_no_text "Edit"
    assert_no_text "Delete"
    assert_no_text "Share this profile"
    assert_no_text "Back to our profiles"
  end

  # ── Wrong user clicks a private group URL ─────────────────────────

  test "wrong user on private group URL sees public group" do
    sign_in_via_browser(@stranger)

    visit our_group_path(@group)

    assert_current_path group_path(@group.uuid)
    assert_text "Friends"

    assert_no_text "Edit"
    assert_no_text "Delete"
    assert_no_text "Manage profiles"
    assert_no_text "Share this group"
  end

  # ── Wrong user on private edit/manage URLs ────────────────────────

  test "wrong user on edit profile URL sees public profile" do
    sign_in_via_browser(@stranger)

    visit edit_our_profile_path(@profile)

    assert_current_path profile_path(@profile.uuid)
    assert_text "Alice"
    assert_no_text "Edit"
    assert_no_text "Delete"
  end

  test "wrong user on edit group URL sees public group" do
    sign_in_via_browser(@stranger)

    visit edit_our_group_path(@group)

    assert_current_path group_path(@group.uuid)
    assert_text "Friends"
    assert_no_text "Edit"
    assert_no_text "Delete"
  end

  test "wrong user on manage profiles URL sees public group" do
    sign_in_via_browser(@stranger)

    visit manage_profiles_our_group_path(@group)

    assert_current_path group_path(@group.uuid)
    assert_text "Friends"
    assert_no_text "Manage profiles"
  end
end
