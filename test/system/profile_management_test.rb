require "application_system_test_case"

class ProfileManagementTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_via_browser
  end

  test "create a new profile" do
    within(".site-header") { click_link "New profile" }
    fill_in "Name", with: "Luna"
    fill_in "Pronouns", with: "she/they"
    fill_in "Description", with: "Hello, I'm Luna!"
    click_button "Create profile"

    assert_text "Profile created."
    assert_text "Luna"
    assert_text "she/they"
  end

  test "edit an existing profile" do
    visit our_profile_path(profiles(:alice))
    click_link "Edit"
    assert_current_path edit_our_profile_path(profiles(:alice))
    fill_in "Name", with: "Alice Updated"
    click_button "Update profile"

    assert_text "Profile updated."
    assert_text "Alice Updated"
  end

  test "delete a profile" do
    visit our_profile_path(profiles(:alice))
    accept_confirm do
      click_link "Delete"
    end

    assert_text "Profile deleted."
  end

  test "view own profile shows share link" do
    visit our_profile_path(profiles(:alice))
    assert_text "Share this profile"
  end

  private

  def sign_in_via_browser
    visit new_session_path
    fill_in "Email address", with: @user.email_address
    fill_in "Password", with: "Plur4l!Pr0files#2026"
    click_button "Sign in"
    assert_current_path root_path
  end
end
