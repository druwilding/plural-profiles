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

  # -- background_image: false (the chat layout) --

  test "background image is included by default" do
    Current.session = nil
    @group_theme = theme_with_background_image
    style = active_theme_style
    assert_includes style, "background-image: url("
    assert_includes style, "background-repeat: repeat;"
  end

  test "background_image: false omits the image but keeps the colours" do
    Current.session = nil
    @group_theme = theme_with_background_image
    style = active_theme_style(background_image: false)

    assert_equal @group_theme.to_css_properties, style
    %w[background-image background-repeat background-size background-position background-attachment].each do |prop|
      assert_not_includes style, "#{prop}:", "expected no #{prop} declaration in chat's theme style"
    end
  end

  test "background_image: false is a no-op for a theme with no image attached" do
    Current.session = nil
    @group_theme = themes(:dark_forest)
    assert_not @group_theme.background_image.attached?
    assert_equal active_theme_style, active_theme_style(background_image: false)
  end

  test "background_image: false applies to the user's own theme too" do
    user = users(:two)
    user.update!(active_theme: theme_with_background_image, override_themes: true)
    Current.session = user.sessions.create!
    assert_not_includes active_theme_style(background_image: false), "background-image:"
  end

  test "background_image: false applies to the site default theme too" do
    Current.session = nil
    themes(:default_shared).background_image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/avatar.png")),
      filename: "bg.png", content_type: "image/png"
    )
    assert_not_includes active_theme_style(background_image: false), "background-image:"
  end

  private

    def theme_with_background_image
      themes(:dark_forest).tap do |theme|
        theme.background_image.attach(
          io: File.open(Rails.root.join("test/fixtures/files/avatar.png")),
          filename: "bg.png", content_type: "image/png"
        )
      end
    end
end
