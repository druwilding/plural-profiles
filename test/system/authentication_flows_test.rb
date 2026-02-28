require "application_system_test_case"

class AuthenticationFlowsTest < ApplicationSystemTestCase
  test "sign in and sign out" do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "Plur4l!Pr0files#2026"
    click_button "Sign in"
    assert_current_path root_path

    within(".site-header") { click_link "Sign out" }
    assert_no_link "Sign out" # wait for signed-out state
  end

  test "sign in with wrong password shows error" do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "Wr0ng!P4ssword#999"
    click_button "Sign in"

    assert_text "Try another email address or password"
  end

  test "register a new account" do
    visit new_registration_path
    fill_in "Invite code", with: invite_codes(:available).code
    fill_in "Email address", with: "newuser@example.com"
    fill_in "Password", with: "N3wUs3r!S1gnup#2026"
    fill_in "Confirm password", with: "N3wUs3r!S1gnup#2026"
    click_button "Sign up"

    assert_text "Account created"
  end

  test "register with invalid invite code shows error" do
    visit new_registration_path
    fill_in "Invite code", with: "BADCODE1"
    fill_in "Email address", with: "newuser@example.com"
    fill_in "Password", with: "N3wUs3r!S1gnup#2026"
    fill_in "Confirm password", with: "N3wUs3r!S1gnup#2026"
    click_button "Sign up"

    assert_text "Invalid or already used invite code"
  end
end
