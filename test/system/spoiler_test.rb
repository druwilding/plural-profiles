require "application_system_test_case"

class SpoilerTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_via_browser
  end

  test "clicking a spoiler reveals it and updates ARIA attributes" do
    within(".site-header") { click_link "New profile" }
    fill_in "Name", with: "Spoiler Tester"
    fill_in "Description", with: "the password is ||super secret||"
    click_button "Create profile"
    assert_text "Profile created."

    spoiler = find(".spoiler")
    assert_no_selector ".spoiler.spoiler--revealed"
    assert_equal "false", spoiler[:"aria-expanded"]
    assert_equal "Hidden content, click to reveal", spoiler[:"aria-label"]

    spoiler.click
    assert_selector ".spoiler.spoiler--revealed"
    assert_text "super secret"
    assert_equal "true", spoiler[:"aria-expanded"]
    assert_equal "Content revealed, click to hide", spoiler[:"aria-label"]
  end

  test "clicking a revealed spoiler hides it again and restores ARIA" do
    within(".site-header") { click_link "New profile" }
    fill_in "Name", with: "Toggle Tester"
    fill_in "Description", with: "||hidden text||"
    click_button "Create profile"
    assert_text "Profile created."

    spoiler = find(".spoiler")
    spoiler.click
    assert_selector ".spoiler.spoiler--revealed"
    assert_equal "true", spoiler[:"aria-expanded"]

    spoiler.click
    assert_no_selector ".spoiler.spoiler--revealed"
    assert_equal "false", spoiler[:"aria-expanded"]
    assert_equal "Hidden content, click to reveal", spoiler[:"aria-label"]
  end

  test "spoiler can be toggled with Enter key" do
    within(".site-header") { click_link "New profile" }
    fill_in "Name", with: "Keyboard Tester"
    fill_in "Description", with: "||keyboard secret||"
    click_button "Create profile"
    assert_text "Profile created."

    spoiler = find(".spoiler")
    assert_no_selector ".spoiler.spoiler--revealed"

    spoiler.send_keys(:enter)
    assert_selector ".spoiler.spoiler--revealed"
    assert_equal "true", spoiler[:"aria-expanded"]

    spoiler.send_keys(:enter)
    assert_no_selector ".spoiler.spoiler--revealed"
    assert_equal "false", spoiler[:"aria-expanded"]
  end

  test "spoiler can be toggled with Space key" do
    within(".site-header") { click_link "New profile" }
    fill_in "Name", with: "Space Tester"
    fill_in "Description", with: "||space secret||"
    click_button "Create profile"
    assert_text "Profile created."

    spoiler = find(".spoiler")
    assert_no_selector ".spoiler.spoiler--revealed"

    spoiler.send_keys(:space)
    assert_selector ".spoiler.spoiler--revealed"
    assert_equal "true", spoiler[:"aria-expanded"]

    spoiler.send_keys(:space)
    assert_no_selector ".spoiler.spoiler--revealed"
    assert_equal "false", spoiler[:"aria-expanded"]
  end

  test "spoiler has correct accessibility attributes" do
    within(".site-header") { click_link "New profile" }
    fill_in "Name", with: "A11y Tester"
    fill_in "Description", with: "||accessible||"
    click_button "Create profile"
    assert_text "Profile created."

    spoiler = find(".spoiler")
    assert_equal "button", spoiler[:"role"]
    assert_equal "0", spoiler[:"tabindex"]
    assert_equal "false", spoiler[:"aria-expanded"]
    assert_equal "Hidden content, click to reveal", spoiler[:"aria-label"]
  end

  test "multiline spoiler is fully revealed on click" do
    within(".site-header") { click_link "New profile" }
    fill_in "Name", with: "Multiline Tester"
    fill_in "Description", with: "||line one\nline two||"
    click_button "Create profile"
    assert_text "Profile created."

    spoiler = find(".spoiler")
    assert_no_selector ".spoiler.spoiler--revealed"

    spoiler.click
    assert_selector ".spoiler.spoiler--revealed"
    assert_text "line one"
    assert_text "line two"
  end

  test "spoiler inside code block is not converted" do
    within(".site-header") { click_link "New profile" }
    fill_in "Name", with: "Code Tester"
    fill_in "Description", with: "Use <code>||text||</code> for spoilers"
    click_button "Create profile"
    assert_text "Profile created."

    assert_selector "code", text: "||text||"
    assert_no_selector "code .spoiler"
  end

  test "details summary can be toggled with keyboard" do
    within(".site-header") { click_link "New profile" }
    fill_in "Name", with: "Details Keyboard Tester"
    fill_in "Description", with: "<details><summary>More info</summary>Hidden detail</details>"
    click_button "Create profile"
    assert_text "Profile created."

    within(".profile-description") do
      summary = find("summary", text: "More info")
      assert_no_selector "details[open]"

      summary.send_keys(:enter)
      assert_selector "details[open]"
      assert_text "Hidden detail"

      summary.send_keys(:enter)
      assert_no_selector "details[open]"
    end
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
