require "application_system_test_case"

class AdminLinkTest < ApplicationSystemTestCase
  test "admins get an Admin link in the header that opens the admin page" do
    sign_in_via_browser(users(:one))
    assert users(:one).admin?

    within(".site-header") { click_link "Admin" }
    assert_selector "h1", text: "Admin"
    click_link "Emotes"
    assert_selector "h1", text: "Emotes"
  end

  test "non-admins get no Admin link" do
    sign_in_via_browser(users(:two))
    assert_not users(:two).admin?
    assert_no_link "Admin"
  end
end
