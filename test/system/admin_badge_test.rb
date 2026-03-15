require "application_system_test_case"

class AdminBadgeTest < ApplicationSystemTestCase
  test "admin badge is visible in the header when signed in as an admin" do
    sign_in_via_browser(users(:one))
    assert users(:one).admin?
    assert_selector ".admin-badge", text: "ADMIN"
  end

  test "admin badge is not visible when signed in as a non-admin" do
    sign_in_via_browser(users(:two))
    assert_not users(:two).admin?
    assert_no_selector ".admin-badge"
  end
end
