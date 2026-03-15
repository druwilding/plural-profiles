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
end
