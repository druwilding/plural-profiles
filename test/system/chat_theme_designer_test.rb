require "application_system_test_case"

# The editor half of themes v3: the per-colour inherit toggle, the live
# inherited swatches, the bulk actions and the chat preview tab.
class ChatThemeDesignerTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @theme = @user.themes.create!(name: "Designer test", colors: { "pane_bg" => "#112233" })
    sign_in_via_browser
  end

  # The designer nests <details> two deep (section, then colour group), and
  # most start collapsed. Opening them all up front keeps these tests about
  # the inherit behaviour rather than about clicking disclosure triangles.
  def open_all_sections
    assert_selector ".theme-designer__color-group", visible: :all
    page.execute_script("document.querySelectorAll('.theme-designer details').forEach(d => d.open = true)")
  end

  def hex_field(property)
    find("input[data-property='#{property}'].theme-designer__hex-input", visible: :all)
  end

  def group_for(property)
    find(".theme-designer__color-group[data-property='#{property}']")
  end

  def override_checkbox(property)
    group_for(property).find("input[type='checkbox']", visible: :all)
  end

  def set_override(property, on)
    box = override_checkbox(property)
    box.click if box.checked? != on
  end

  test "a chat colour starts inherited, showing the profile colour it follows" do
    visit edit_our_theme_path(@theme)
    open_all_sections

    assert_equal "#112233", hex_field("chat_pane_bg").value
    assert hex_field("chat_pane_bg").disabled?, "an inherited colour's input should not be editable"
    assert_text "Following"
  end

  test "switching to 'Set for chat' enables the picker and stores the colour" do
    visit edit_our_theme_path(@theme)
    open_all_sections
    set_override("chat_pane_bg", true)

    assert_not hex_field("chat_pane_bg").disabled?
    hex_field("chat_pane_bg").set("#ff0000")
    click_button "Save theme"
    assert_text "Changes saved."

    assert_equal "#ff0000", @theme.reload.colors["chat_pane_bg"]
  end

  test "switching back to 'Use profile colour' removes the stored override" do
    @theme.update!(colors: { "pane_bg" => "#112233", "chat_pane_bg" => "#ff0000" })
    visit edit_our_theme_path(@theme)
    open_all_sections

    assert_not hex_field("chat_pane_bg").disabled?, "a stored override should start editable"
    set_override("chat_pane_bg", false)
    assert hex_field("chat_pane_bg").disabled?

    click_button "Save theme"
    assert_text "Changes saved."

    assert_not @theme.reload.colors.key?("chat_pane_bg")
    assert_equal "#112233", @theme.color_for("chat_pane_bg"), "it should be following pane_bg again"
  end

  test "editing a profile colour moves the chat colours still following it" do
    visit edit_our_theme_path(@theme)
    open_all_sections
    assert_equal "#112233", hex_field("chat_pane_bg").value

    hex_field("pane_bg").set("#00ff00")

    # Both the direct child and the two-hop grandchild
    # (chat_topbar_bg -> chat_pane_bg -> pane_bg) should follow along.
    assert_equal "#00ff00", hex_field("chat_pane_bg").value
    assert_equal "#00ff00", hex_field("chat_topbar_bg").value
  end

  test "an overridden chat colour stops following its profile colour" do
    visit edit_our_theme_path(@theme)
    open_all_sections
    set_override("chat_pane_bg", true)
    hex_field("chat_pane_bg").set("#ff0000")

    hex_field("pane_bg").set("#00ff00")

    assert_equal "#ff0000", hex_field("chat_pane_bg").value, "an override should not be overwritten"
    assert_equal "#ff0000", hex_field("chat_topbar_bg").value, "the topbar should follow its nearest set ancestor"
  end

  test "the override checkbox reflects the stored state on load" do
    @theme.update!(colors: { "pane_bg" => "#112233", "chat_rail_bg" => "#ff0000" })
    visit edit_our_theme_path(@theme)
    open_all_sections

    assert override_checkbox("chat_rail_bg").checked?, "a stored override should load ticked"
    assert_not override_checkbox("chat_pane_bg").checked?, "an inherited colour should load unticked"
  end

  test "the JSON export omits inherited colours and names version 3" do
    visit edit_our_theme_path(@theme)
    open_all_sections
    set_override("chat_rail_bg", true)
    hex_field("chat_rail_bg").set("#abcdef")

    exported = JSON.parse(find(".theme-designer__css-output", visible: :all).value)

    assert_equal 3, exported["plural_profiles_theme"]
    assert_equal "#abcdef", exported["colors"]["chat_rail_bg"]
    assert_not exported["colors"].key?("chat_pane_bg"), "an inherited colour must not export as an override"
  end

  test "the chat preview tab shows a chat mock that responds to chat colours" do
    visit edit_our_theme_path(@theme)
    assert_selector ".theme-preview__panel[data-preview-panel='profile']", visible: true

    click_button "Chat"
    assert_selector ".theme-preview__chat", visible: true

    open_all_sections
    set_override("chat_rail_bg", true)
    hex_field("chat_rail_bg").set("#ff0000")

    rail = find(".theme-preview__chat .server-rail")
    assert_equal "rgba(255, 0, 0, 1)", rail.native.style("background-color")
  end
end
