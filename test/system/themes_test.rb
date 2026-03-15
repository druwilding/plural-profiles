require "application_system_test_case"

class ThemesTest < ApplicationSystemTestCase
  # -- Default theme UI --

  test "admin sees Make default button on a non-default shared theme" do
    sign_in_via_browser(users(:one))
    visit our_themes_path

    within(".card", text: "Ocean Shared") do
      assert_link "Make default"
      assert_no_link "Remove default"
    end
  end

  test "admin sees Remove default button on the current default theme" do
    sign_in_via_browser(users(:one))
    visit our_themes_path

    within(".card", text: "Default Shared") do
      assert_link "Remove default"
      assert_no_link "Make default"
    end
  end

  test "admin can set a shared theme as default from the index" do
    sign_in_via_browser(users(:one))
    visit our_themes_path

    within(".card", text: "Ocean Shared") do
      click_link "Make default"
    end

    assert_text "'Ocean Shared' is now the default theme"

    within(".card", text: "Ocean Shared") do
      assert_link "Remove default"
      assert_text "Default theme"
    end
  end

  test "admin can remove default from a theme from the index" do
    sign_in_via_browser(users(:one))
    visit our_themes_path

    within(".card", text: "Default Shared") do
      click_link "Remove default"
    end

    assert_text "'Default Shared' is no longer the default theme"

    within(".card", text: "Default Shared") do
      assert_link "Make default"
      assert_no_text "Default theme"
    end
  end

  test "non-admin does not see Make default or Remove default buttons" do
    sign_in_via_browser(users(:two))
    visit our_themes_path

    assert_no_link "Make default"
    assert_no_link "Remove default"
  end

  test "non-admin can still see the Default theme badge on the index" do
    sign_in_via_browser(users(:two))
    visit our_themes_path

    within(".card", text: "Default Shared") do
      assert_text "Default theme"
    end
  end

  test "admin sees Make default button on the theme show page" do
    sign_in_via_browser(users(:one))
    visit our_theme_path(themes(:ocean_shared))

    assert_link "Make default"
    assert_no_link "Remove default"
  end

  test "admin sees Remove default button on the default theme show page" do
    sign_in_via_browser(users(:one))
    visit our_theme_path(themes(:default_shared))

    assert_link "Remove default"
    assert_no_link "Make default"
    assert_text "Default theme"
  end

  test "non-admin does not see Make default or Remove default on the show page" do
    sign_in_via_browser(users(:two))
    visit our_theme_path(themes(:ocean_shared))

    assert_no_link "Make default"
    assert_no_link "Remove default"
  end
end
