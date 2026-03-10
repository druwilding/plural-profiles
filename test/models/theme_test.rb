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
    assert_includes groups, :buttons
    assert_includes groups, :forms
    assert_includes groups, :flash
  end
end
