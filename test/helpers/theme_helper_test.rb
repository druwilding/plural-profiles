require "test_helper"

class ThemeHelperTest < ActionView::TestCase
  # authenticated? is defined in the Authentication controller concern and exposed
  # via helper_method. Provide a view-test-compatible version that mirrors the
  # real behaviour: returns truthy when a session is present.
  helper do
    def authenticated?
      Current.session.present?
    end
  end

  setup do
    Rails.cache.clear
  end

  teardown do
    Current.session&.destroy
    Current.reset
    Rails.cache.clear
  end

  # -- active_theme_style --

  test "logged-out visitor sees the default theme's CSS" do
    Current.session = nil
    assert_equal themes(:default_shared).to_css_properties, active_theme_style
  end

  test "logged-in user without an active theme sees the default theme's CSS" do
    Current.session = users(:two).sessions.create!
    assert_nil Current.user.active_theme
    assert_equal themes(:default_shared).to_css_properties, active_theme_style
  end

  test "logged-in user with an active theme sees their own theme's CSS" do
    user = users(:two)
    user.update!(active_theme: themes(:other_user_theme))
    Current.session = user.sessions.create!
    assert_equal themes(:other_user_theme).to_css_properties, active_theme_style
  end

  test "returns nil when no default theme is set and the user is logged out" do
    themes(:default_shared).update!(site_default: false)
    Current.session = nil
    assert_nil active_theme_style
  end

  # -- group theme (@group_theme) --

  test "unauthenticated visitor with a group theme sees the group theme's CSS" do
    Current.session = nil
    @group_theme = themes(:dark_forest)
    assert_equal themes(:dark_forest).to_css_properties, active_theme_style
  end

  test "logged-in user with active theme and no override sees the group theme" do
    user = users(:two)
    user.update!(active_theme: themes(:other_user_theme), override_themes: false)
    Current.session = user.sessions.create!
    @group_theme = themes(:dark_forest)
    assert_equal themes(:dark_forest).to_css_properties, active_theme_style
  end

  test "logged-in user with active theme and override enabled sees their own theme" do
    user = users(:two)
    user.update!(active_theme: themes(:other_user_theme), override_themes: true)
    Current.session = user.sessions.create!
    @group_theme = themes(:dark_forest)
    assert_equal themes(:other_user_theme).to_css_properties, active_theme_style
  end

  test "logged-in user with no active theme and override on sees the site default, not the group theme" do
    user = users(:two)
    assert_nil user.active_theme
    user.update!(override_themes: true)
    Current.session = user.sessions.create!
    @group_theme = themes(:dark_forest)
    assert_equal themes(:default_shared).to_css_properties, active_theme_style
  end

  # -- profile theme (@profile_theme) --

  test "unauthenticated visitor with a profile theme sees the profile theme's CSS" do
    Current.session = nil
    @profile_theme = themes(:dark_forest)
    assert_equal themes(:dark_forest).to_css_properties, active_theme_style
  end

  test "logged-in user with active theme and no override sees the profile theme" do
    user = users(:two)
    user.update!(active_theme: themes(:other_user_theme), override_themes: false)
    Current.session = user.sessions.create!
    @profile_theme = themes(:dark_forest)
    assert_equal themes(:dark_forest).to_css_properties, active_theme_style
  end

  test "logged-in user with active theme and override enabled sees their own theme over profile theme" do
    user = users(:two)
    user.update!(active_theme: themes(:other_user_theme), override_themes: true)
    Current.session = user.sessions.create!
    @profile_theme = themes(:dark_forest)
    assert_equal themes(:other_user_theme).to_css_properties, active_theme_style
  end

  test "group theme takes priority over profile theme" do
    Current.session = nil
    @group_theme = themes(:sunset)
    @profile_theme = themes(:dark_forest)
    assert_equal themes(:sunset).to_css_properties, active_theme_style
  end
end
