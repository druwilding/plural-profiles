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
end
