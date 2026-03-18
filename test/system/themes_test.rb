require "application_system_test_case"

class ThemesTest < ApplicationSystemTestCase
  # -- Default theme UI --

  test "admin sees Make default button on a non-default shared theme" do
    sign_in_via_browser(users(:one))
    visit our_themes_path

    within(:css, "[data-theme-section='shared'][data-theme-id='#{themes(:ocean_shared).id}']") do
      assert_link "Make default"
      assert_no_link "Remove default"
    end
  end

  test "admin sees Remove default button on the current default theme" do
    sign_in_via_browser(users(:one))
    visit our_themes_path

    within(:css, "[data-theme-section='shared'][data-theme-id='#{themes(:default_shared).id}']") do
      assert_link "Remove default"
      assert_no_link "Make default"
    end
  end

  test "admin can set a shared theme as default from the index" do
    sign_in_via_browser(users(:one))
    visit our_themes_path

    within(:css, "[data-theme-section='shared'][data-theme-id='#{themes(:ocean_shared).id}']") do
      click_link "Make default"
    end

    assert_text "'Ocean Shared' is now the default theme"

    within(:css, "[data-theme-section='shared'][data-theme-id='#{themes(:ocean_shared).id}']") do
      assert_link "Remove default"
      assert_text "Default theme"
    end
  end

  test "admin can remove default from a theme from the index" do
    sign_in_via_browser(users(:one))
    visit our_themes_path

    within(:css, "[data-theme-section='shared'][data-theme-id='#{themes(:default_shared).id}']") do
      click_link "Remove default"
    end

    assert_text "'Default Shared' is no longer the default theme"

    within(:css, "[data-theme-section='shared'][data-theme-id='#{themes(:default_shared).id}']") do
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


  # -- Theme credit footer on public group pages --

  test "public group page with a theme shows theme name in footer" do
    sign_in_via_browser(users(:one))
    visit group_path(groups(:friends).uuid)
    assert_css ".theme-credit"
    assert_text "Theme: Dark Forest"
  end

  test "public group page with a theme shows Made by credit" do
    sign_in_via_browser(users(:one))
    visit group_path(groups(:friends).uuid)
    assert_text "by Verdant Studio"
  end

  test "public group page with a theme links to credit_url" do
    sign_in_via_browser(users(:one))
    visit group_path(groups(:friends).uuid)
    assert_link "Verdant Studio", href: "https://example.com/verdant"
  end

  test "public group page without a theme shows no theme credit footer" do
    sign_in_via_browser(users(:one))
    visit group_path(groups(:everyone).uuid)
    assert_no_css ".theme-credit"
  end

  test "group profile page with a group theme shows theme name in footer" do
    profile = groups(:friends).profiles.first
    skip "friends group has no profiles" if profile.nil?
    sign_in_via_browser(users(:one))
    visit group_profile_path(groups(:friends).uuid, profile.uuid)
    assert_css ".theme-credit"
    assert_text "Theme: Dark Forest"
  end

  # -- Theme credit footer on public profile pages --

  test "public profile page with a group theme shows theme name in footer" do
    profile = groups(:friends).profiles.first
    skip "friends group has no profiles" if profile.nil?
    sign_in_via_browser(users(:one))
    visit profile_path(profile.uuid)
    assert_css ".theme-credit"
    assert_text "Theme: Dark Forest"
  end

  test "public profile page with a group theme shows Made by credit" do
    profile = groups(:friends).profiles.first
    skip "friends group has no profiles" if profile.nil?
    sign_in_via_browser(users(:one))
    visit profile_path(profile.uuid)
    assert_text "by Verdant Studio"
  end

  test "public profile page with a group theme links to credit_url" do
    profile = groups(:friends).profiles.first
    skip "friends group has no profiles" if profile.nil?
    sign_in_via_browser(users(:one))
    visit profile_path(profile.uuid)
    assert_link "Verdant Studio", href: "https://example.com/verdant"
  end

  test "public profile page without a group theme shows no theme credit footer" do
    profile = groups(:everyone).profiles.first
    skip "everyone group has no profiles" if profile.nil?
    sign_in_via_browser(users(:one))
    visit profile_path(profile.uuid)
    assert_no_css ".theme-credit"
  end

  # -- override_themes preference --
  # friends group uses dark_forest (page-bg: #0e2e24)
  # everyone group has no theme
  # sunset: page-bg #2e1a0e  |  ocean_shared: page-bg #0e1e2e  |  default_shared: page-bg #1a1a2e

  test "override on with a personal active theme: sees own theme on a group page" do
    users(:one).update!(active_theme: themes(:sunset), override_themes: true)
    sign_in_via_browser(users(:one))
    visit group_path(groups(:friends).uuid)
    assert_includes find("body")[:style], "--page-bg: #2e1a0e"
  end

  test "override on with a personal active theme: sees own theme on a profile page" do
    users(:one).update!(active_theme: themes(:sunset), override_themes: true)
    sign_in_via_browser(users(:one))
    profile = groups(:friends).profiles.first
    skip "friends group has no profiles" if profile.nil?
    visit profile_path(profile.uuid)
    assert_includes find("body")[:style], "--page-bg: #2e1a0e"
  end

  test "override on with a shared active theme: sees own theme on a group page" do
    users(:one).update!(active_theme: themes(:ocean_shared), override_themes: true)
    sign_in_via_browser(users(:one))
    visit group_path(groups(:friends).uuid)
    assert_includes find("body")[:style], "--page-bg: #0e1e2e"
  end

  test "override on with a shared active theme: sees own theme on a profile page" do
    users(:one).update!(active_theme: themes(:ocean_shared), override_themes: true)
    sign_in_via_browser(users(:one))
    profile = groups(:friends).profiles.first
    skip "friends group has no profiles" if profile.nil?
    visit profile_path(profile.uuid)
    assert_includes find("body")[:style], "--page-bg: #0e1e2e"
  end

  test "override on but no active theme set: default theme applies instead of group theme" do
    users(:one).update!(active_theme: nil, override_themes: true)
    sign_in_via_browser(users(:one))
    visit group_path(groups(:friends).uuid)
    assert_includes find("body")[:style], "--page-bg: #1a1a2e"
  end

  test "override on but no active theme set: default theme applies instead of group theme on profile page" do
    users(:one).update!(active_theme: nil, override_themes: true)
    sign_in_via_browser(users(:one))
    profile = groups(:friends).profiles.first
    skip "friends group has no profiles" if profile.nil?
    visit profile_path(profile.uuid)
    assert_includes find("body")[:style], "--page-bg: #1a1a2e"
  end

  test "override off with a personal active theme: group theme takes precedence" do
    users(:one).update!(active_theme: themes(:sunset), override_themes: false)
    sign_in_via_browser(users(:one))
    visit group_path(groups(:friends).uuid)
    assert_includes find("body")[:style], "--page-bg: #0e2e24"
  end

  test "override off with a personal active theme: group theme takes precedence on profile page" do
    users(:one).update!(active_theme: themes(:sunset), override_themes: false)
    sign_in_via_browser(users(:one))
    profile = groups(:friends).profiles.first
    skip "friends group has no profiles" if profile.nil?
    visit profile_path(profile.uuid)
    assert_includes find("body")[:style], "--page-bg: #0e2e24"
  end

  test "override off on a group with no theme: own active theme still applies" do
    users(:one).update!(active_theme: themes(:sunset), override_themes: false)
    sign_in_via_browser(users(:one))
    visit group_path(groups(:everyone).uuid)
    assert_includes find("body")[:style], "--page-bg: #2e1a0e"
  end

  test "override off on a profile with no group theme: own active theme still applies" do
    users(:one).update!(active_theme: themes(:sunset), override_themes: false)
    sign_in_via_browser(users(:one))
    profile = groups(:everyone).profiles.first
    skip "everyone group has no profiles" if profile.nil?
    visit profile_path(profile.uuid)
    assert_includes find("body")[:style], "--page-bg: #2e1a0e"
  end

  # -- Import theme with alpha --

  test "import theme accepts 8-digit hex colors with alpha" do
    sign_in_via_browser(users(:one))
    visit our_themes_path

    click_button "Import theme"

    css_block = <<~CSS
      :root {
        --page-bg: #12345678;
        --text: #aabbccdd;
        --link: #ff0000ff;
      }
    CSS

    find("textarea.import-dialog__textarea").set(css_block)
    click_button "Import"

    # Should redirect to new theme page with colors pre-filled
    assert_current_path new_our_theme_path, ignore_query: true
    assert_equal "#12345678", find("input[name='theme[colors][page_bg]'].theme-designer__hex-input").value
    assert_equal "#aabbccdd", find("input[name='theme[colors][text]'].theme-designer__hex-input").value
    assert_equal "#ff0000ff", find("input[name='theme[colors][link]'].theme-designer__hex-input").value
  end
end
