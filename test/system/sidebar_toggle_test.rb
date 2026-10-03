require "application_system_test_case"

class SidebarToggleTest < ApplicationSystemTestCase
  setup do
    sign_in_via_browser(users(:one))
    visit our_profiles_path
  end

  test "hiding the sidebar lasts across reloads and other pages until it's shown again" do
    assert_selector "nav.sidebar"
    click_button "Hide sidebar"

    assert_no_selector "nav.sidebar"
    assert_selector ".layout--sidebar-hidden"
    assert_selector "button.sidebar-show:focus"

    refresh
    assert_no_selector "nav.sidebar"
    assert_button "Show sidebar"

    visit our_themes_path
    assert_no_selector "nav.sidebar"

    click_button "Show sidebar"
    assert_selector "nav.sidebar"
    assert_selector "button.sidebar__hide:focus"
    assert_no_button "Show sidebar"

    visit our_profiles_path
    assert_selector "nav.sidebar"
  end
end
