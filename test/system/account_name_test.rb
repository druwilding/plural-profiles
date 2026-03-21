require "application_system_test_case"

class AccountNameTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @password = "Plur4l!Pr0files#2026"
  end

  # -- Account page display --

  test "account page shows the account name section" do
    sign_in_via_browser
    click_link "Account"

    within(".card", text: "Account name") do
      assert_text "Account name"
      assert_text "lets others find and connect"
    end
  end

  test "account page shows prompt to set account name when none is set" do
    @user.update!(username: nil)
    sign_in_via_browser
    click_link "Account"

    within(".card", text: "Account name") do
      assert_selector "input[type='submit'][value='Set account name']"
      assert_no_text "Current account name:"
    end
  end

  test "account page shows current account name when one is set" do
    @user.update!(username: "myhandle")
    sign_in_via_browser
    click_link "Account"

    within(".card", text: "Account name") do
      assert_text "Current account name:"
      assert_text "myhandle"
      assert_selector "input[type='submit'][value='Change account name']"
    end
  end

  # -- Setting / changing account name --

  test "set account name when none exists" do
    @user.update!(username: nil)
    sign_in_via_browser
    click_link "Account"

    within(".card", text: "Account name") do
      fill_in "Account name", with: "newhandle"
      click_button "Set account name"
    end

    assert_text "Account name updated"
    within(".card", text: "Account name") do
      assert_text "Current account name:"
      assert_text "newhandle"
    end

    assert_equal "newhandle", @user.reload.username
  end

  test "change existing account name" do
    @user.update!(username: "oldhandle")
    sign_in_via_browser
    click_link "Account"

    within(".card", text: "Account name") do
      fill_in "Account name", with: "newhandle"
      click_button "Change account name"
    end

    assert_text "Account name updated"
    within(".card", text: "Account name") do
      assert_text "newhandle"
    end

    assert_equal "newhandle", @user.reload.username
  end

  test "old account name no longer works after changing it" do
    @user.update!(username: "oldhandle")
    sign_in_via_browser
    click_link "Account"

    within(".card", text: "Account name") do
      fill_in "Account name", with: "newhandle"
      click_button "Change account name"
    end

    assert_text "Account name updated"

    within(".site-header") { click_link "Sign out" }
    assert_no_link "Sign out"

    # Old name should no longer work
    fill_in "Email address or account name", with: "oldhandle"
    fill_in "Password", with: @password
    click_button "Sign in"

    assert_text "Try another email address or password"
    assert_current_path new_session_path

    # New name should work
    fill_in "Email address or account name", with: "newhandle"
    fill_in "Password", with: @password
    click_button "Sign in"

    assert_current_path root_path
  end

  test "account name is displayed in lowercase even when entered in mixed case" do
    @user.update!(username: nil)
    sign_in_via_browser
    click_link "Account"

    within(".card", text: "Account name") do
      fill_in "Account name", with: "MyHandle"
      click_button "Set account name"
    end

    assert_text "Account name updated"
    assert_equal "myhandle", @user.reload.username
  end

  test "clear account name by submitting blank" do
    @user.update!(username: "clearme")
    sign_in_via_browser
    click_link "Account"

    within(".card", text: "Account name") do
      fill_in "Account name", with: ""
      click_button "Change account name"
    end

    assert_text "Account name updated"
    within(".card", text: "Account name") do
      assert_no_text "Current account name:"
      assert_selector "input[type='submit'][value='Set account name']"
    end

    assert_nil @user.reload.username
  end

  # -- Validation errors --

  test "invalid account name with leading underscore shows an error" do
    @user.update!(username: nil)
    sign_in_via_browser
    click_link "Account"

    within(".card", text: "Account name") do
      fill_in "Account name", with: "_badstart"
      click_button "Set account name"
    end

    assert_text "Account name"
    within(".card", text: "Account name") do
      assert_selector ".error-messages"
    end
  end

  test "invalid account name with consecutive hyphens shows an error" do
    @user.update!(username: nil)
    sign_in_via_browser
    click_link "Account"

    within(".card", text: "Account name") do
      fill_in "Account name", with: "bad--name"
      click_button "Set account name"
    end

    within(".card", text: "Account name") do
      assert_selector ".error-messages"
    end
  end

  test "account name that is too short shows an error" do
    @user.update!(username: nil)
    sign_in_via_browser
    click_link "Account"

    within(".card", text: "Account name") do
      # Remove the minlength attribute so the form can submit
      execute_script("document.querySelector('input#user_username').removeAttribute('minlength')")
      fill_in "Account name", with: "x"
      click_button "Set account name"
    end

    within(".card", text: "Account name") do
      assert_selector ".error-messages"
    end
  end

  test "duplicate account name shows an error" do
    users(:two).update!(username: "taken")
    @user.update!(username: nil)
    sign_in_via_browser
    click_link "Account"

    within(".card", text: "Account name") do
      fill_in "Account name", with: "taken"
      click_button "Set account name"
    end

    within(".card", text: "Account name") do
      assert_selector ".error-messages"
      assert_text "already been taken"
    end
  end

  # -- Login with account name --

  test "sign in with account name" do
    @user.update!(username: "logintest")

    visit new_session_path
    fill_in "Email address or account name", with: "logintest"
    fill_in "Password", with: @password
    click_button "Sign in"

    assert_current_path root_path
  end

  test "sign in with account name is case-insensitive" do
    @user.update!(username: "logintest")

    visit new_session_path
    fill_in "Email address or account name", with: "LoginTest"
    fill_in "Password", with: @password
    click_button "Sign in"

    assert_current_path root_path
  end

  test "sign in with wrong password for account name shows error" do
    @user.update!(username: "logintest")

    visit new_session_path
    fill_in "Email address or account name", with: "logintest"
    fill_in "Password", with: "wr0ngpassword"
    click_button "Sign in"

    assert_text "Try another email address or password"
    assert_current_path new_session_path
  end

  test "sign in with non-existent account name shows error" do
    visit new_session_path
    fill_in "Email address or account name", with: "doesnotexist"
    fill_in "Password", with: @password
    click_button "Sign in"

    assert_text "Try another email address or password"
    assert_current_path new_session_path
  end

  test "sign in with account name for deactivated account shows error" do
    @user.update!(username: "deactivateduser")
    @user.deactivate!

    visit new_session_path
    fill_in "Email address or account name", with: "deactivateduser"
    fill_in "Password", with: @password
    click_button "Sign in"

    assert_text "Try another email address or password"
    assert_current_path new_session_path
  end

  # -- Registration with optional account name --

  test "registration form has an optional account name field" do
    visit new_registration_path

    assert_selector "input[name='user[username]']"
    assert_text "Account name (optional)"
  end

  test "register with a valid account name saves it" do
    visit new_registration_path
    fill_in "Invite code", with: invite_codes(:available).code
    fill_in "Account name (optional)", with: "brandnew"
    fill_in "Email address", with: "withname@example.com"
    fill_in "Password", with: "N3wUs3r!S1gnup#2026"
    fill_in "Confirm password", with: "N3wUs3r!S1gnup#2026"
    check "I agree to these terms"
    click_button "Sign up"

    assert_text "Account created"
    assert_equal "brandnew", User.find_by(email_address: "withname@example.com").username
  end

  test "register without an account name is allowed" do
    visit new_registration_path
    fill_in "Invite code", with: invite_codes(:available).code
    fill_in "Email address", with: "noname@example.com"
    fill_in "Password", with: "N3wUs3r!S1gnup#2026"
    fill_in "Confirm password", with: "N3wUs3r!S1gnup#2026"
    check "I agree to these terms"
    click_button "Sign up"

    assert_text "Account created"
    assert_nil User.find_by(email_address: "noname@example.com").username
  end

  test "register with an invalid account name shows errors" do
    visit new_registration_path
    fill_in "Invite code", with: invite_codes(:available).code
    # Remove the pattern attribute so the browser lets the form submit
    execute_script("document.querySelector('input#user_username').removeAttribute('pattern')")
    fill_in "Account name (optional)", with: "_invalid"
    fill_in "Email address", with: "invalidname@example.com"
    fill_in "Password", with: "N3wUs3r!S1gnup#2026"
    fill_in "Confirm password", with: "N3wUs3r!S1gnup#2026"
    check "I agree to these terms"
    click_button "Sign up"

    assert_text "Account name"
    assert_no_text "Account created"
  end

  test "register with a duplicate account name shows errors" do
    users(:one).update!(username: "dupname")

    visit new_registration_path
    fill_in "Invite code", with: invite_codes(:available).code
    # Remove the pattern attribute so the browser lets the form submit
    execute_script("document.querySelector('input#user_username').removeAttribute('pattern')")
    fill_in "Account name (optional)", with: "dupname"
    fill_in "Email address", with: "dup@example.com"
    fill_in "Password", with: "N3wUs3r!S1gnup#2026"
    fill_in "Confirm password", with: "N3wUs3r!S1gnup#2026"
    check "I agree to these terms"
    click_button "Sign up"

    assert_text "Account name"
    assert_no_text "Account created"
  end
end
