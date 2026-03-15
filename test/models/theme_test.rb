require "test_helper"

class ThemeTest < ActiveSupport::TestCase
  test "requires name" do
    theme = Theme.new(user: users(:one), colors: { "page_bg" => "#000000" })
    assert_not theme.valid?
    assert_includes theme.errors[:name], "can't be blank"
  end

  test "requires colors" do
    theme = Theme.new(user: users(:one), name: "Test")
    theme.colors = nil
    assert_not theme.valid?
    assert_includes theme.errors[:colors], "must be a hash"
  end

  test "belongs to user" do
    assert_equal users(:one), themes(:dark_forest).user
  end

  test "color_for returns stored colour" do
    theme = themes(:dark_forest)
    assert_equal "#0e2e24", theme.color_for("page_bg")
  end

  test "color_for falls back to default" do
    theme = Theme.new(user: users(:one), name: "Empty", colors: {})
    assert_equal "#0e2e24", theme.color_for("page_bg")
  end

  test "to_css_properties generates inline style string" do
    theme = themes(:dark_forest)
    css = theme.to_css_properties
    assert_includes css, "--page-bg: #0e2e24;"
    assert_includes css, "--pane-bg: #133b2f;"
    assert_includes css, "--link: #3ab580;"
  end

  test "to_css generates a full root block" do
    theme = themes(:dark_forest)
    css = theme.to_css
    assert css.start_with?(":root {")
    assert css.end_with?("}")
    assert_includes css, "  --page-bg: #0e2e24;"
  end

  test "THEMEABLE_PROPERTIES covers all expected groups" do
    groups = Theme::THEMEABLE_PROPERTIES.values.map { |v| v[:group] }.uniq
    assert_includes groups, :base
    assert_includes groups, :forms
    assert_includes groups, :buttons
    assert_includes groups, :flash
  end

  # -- Tags --

  test "tags default to empty array" do
    theme = Theme.new(user: users(:one), name: "Tagless", colors: {})
    assert_equal [], theme.tags
  end

  test "TAGS is a non-empty hash" do
    assert_kind_of Hash, Theme::TAGS
    assert Theme::TAGS.any?
  end

  test "valid with known tags" do
    theme = Theme.new(user: users(:one), name: "Tagged", colors: {}, tags: [ "dark", "high-contrast" ])
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "valid with empty tags" do
    theme = Theme.new(user: users(:one), name: "No tags", colors: {}, tags: [])
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "invalid with unknown tag" do
    theme = Theme.new(user: users(:one), name: "Bad tag", colors: {}, tags: [ "unknown-tag" ])
    assert_not theme.valid?
    assert_match "unknown-tag", theme.errors[:tags].to_sentence
  end

  test "fixture dark_forest has expected tags" do
    assert_equal [ "dark", "cool-colours" ], themes(:dark_forest).tags
  end

  test "fixture sunset has expected tags" do
    assert_equal [ "light", "warm-colours" ], themes(:sunset).tags
  end

  # -- Credit & notes --

  test "valid with credit and notes" do
    theme = Theme.new(user: users(:one), name: "Credited", colors: {}, credit: "Dru", notes: "My notes")
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "valid without credit and notes" do
    theme = Theme.new(user: users(:one), name: "Plain", colors: {})
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "credit over 255 characters is invalid" do
    theme = Theme.new(user: users(:one), name: "Long credit", colors: {}, credit: "a" * 256)
    assert_not theme.valid?
    assert_includes theme.errors[:credit], "is too long (maximum is 255 characters)"
  end

  test "credit at exactly 255 characters is valid" do
    theme = Theme.new(user: users(:one), name: "Max credit", colors: {}, credit: "a" * 255)
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  # -- Credit URL --

  test "valid with a https credit_url" do
    theme = Theme.new(user: users(:one), name: "Linked", colors: {}, credit_url: "https://example.com")
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "valid with a http credit_url" do
    theme = Theme.new(user: users(:one), name: "Linked", colors: {}, credit_url: "http://example.com")
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "valid without credit_url" do
    theme = Theme.new(user: users(:one), name: "No link", colors: {})
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "invalid credit_url without scheme" do
    theme = Theme.new(user: users(:one), name: "Bad link", colors: {}, credit_url: "example.com")
    assert_not theme.valid?
    assert_includes theme.errors[:credit_url], "must be a valid http or https URL"
  end

  test "invalid credit_url with ftp scheme" do
    theme = Theme.new(user: users(:one), name: "FTP", colors: {}, credit_url: "ftp://example.com")
    assert_not theme.valid?
    assert_includes theme.errors[:credit_url], "must be a valid http or https URL"
  end

  test "credit_url over 255 characters is invalid" do
    theme = Theme.new(user: users(:one), name: "Long URL", colors: {}, credit_url: "https://" + "a" * 248)
    assert_not theme.valid?
    assert_includes theme.errors[:credit_url], "is too long (maximum is 255 characters)"
  end

  # -- Shared themes --

  test "admin user can create a shared theme" do
    theme = Theme.new(user: users(:one), name: "Admin shared", colors: {}, shared: true)
    assert users(:one).admin?, "fixture user one should be admin"
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "non-admin user cannot create a shared theme" do
    theme = Theme.new(user: users(:two), name: "Non-admin shared", colors: {}, shared: true)
    assert_not users(:two).admin?
    assert_not theme.valid?
    assert_includes theme.errors[:shared], "can only be set by admins"
  end

  test "non-admin theme with shared false is valid" do
    theme = Theme.new(user: users(:two), name: "Non-admin personal", colors: {}, shared: false)
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "shared scope returns only shared themes" do
    shared = Theme.shared
    assert_includes shared, themes(:ocean_shared)
    assert_not_includes shared, themes(:dark_forest)
    assert_not_includes shared, themes(:sunset)
  end

  test "personal scope returns only non-shared themes" do
    personal = Theme.personal
    assert_not_includes personal, themes(:ocean_shared)
    assert_includes personal, themes(:dark_forest)
    assert_includes personal, themes(:sunset)
  end

  # -- Default theme --

  test "site_default can only be set on shared themes" do
    theme = Theme.new(user: users(:one), name: "Personal Default", colors: {}, shared: false, site_default: true)
    assert_not theme.valid?
    assert_includes theme.errors[:site_default], "can only be set on shared themes"
  end

  test "site_default on a shared theme is valid" do
    theme = Theme.new(user: users(:one), name: "Shared Default", colors: {}, shared: true, site_default: true)
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "site_default_theme returns the default theme" do
    Rails.cache.clear
    assert_equal themes(:default_shared), Theme.site_default_theme
  end

  test "site_default_theme returns nil when no default is set" do
    Rails.cache.clear
    themes(:default_shared).update!(site_default: false)
    assert_nil Theme.site_default_theme
  end

  test "setting site_default clears it on other themes" do
    Rails.cache.clear
    themes(:ocean_shared).update!(site_default: true)
    assert themes(:ocean_shared).reload.site_default?
    assert_not themes(:default_shared).reload.site_default?
  end

  test "destroying the default theme busts the cache" do
    Rails.cache.clear
    # Warm the cache
    Theme.site_default_theme
    # Destroy the default theme — cache should be busted
    themes(:default_shared).destroy
    assert_nil Theme.site_default_theme
  end
end
