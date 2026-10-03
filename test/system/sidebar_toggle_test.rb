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
    assert_selector "button.sidebar-toggle--show:focus"

    refresh
    assert_no_selector "nav.sidebar"
    assert_button "Show sidebar"

    visit our_themes_path
    assert_no_selector "nav.sidebar"

    click_button "Show sidebar"
    assert_selector "nav.sidebar"
    assert_selector "button.sidebar-toggle--hide:focus"
    assert_no_button "Show sidebar"

    visit our_profiles_path
    assert_selector "nav.sidebar"
  end

  test "a public group page's sidebar hides and shows on its own, separately from ours" do
    group_page = group_path(groups(:alpha_clan).uuid)
    visit group_page
    assert_selector ".explorer__sidebar"
    click_button "Hide sidebar"

    assert_no_selector ".explorer__sidebar"
    assert_selector ".explorer--sidebar-hidden"
    assert_selector "button.sidebar-toggle--show:focus"
    within(".explorer__content") { assert_selector ".profile-card h3", text: "Grove" }

    refresh
    assert_no_selector ".explorer__sidebar"

    # Our own sidebar is still shown...
    visit our_profiles_path
    assert_selector "nav.sidebar"

    # ...and hiding it doesn't bring back the group page's.
    click_button "Hide sidebar"
    visit group_page
    assert_no_selector ".explorer__sidebar"

    click_button "Show sidebar"
    assert_selector ".explorer__sidebar"
    assert_selector "button.sidebar-toggle--hide:focus"

    visit our_profiles_path
    assert_no_selector "nav.sidebar"
  end

  test "in forced colors the round hide and show buttons are drawn like default buttons" do
    with_forced_colors do
      probe = page.evaluate_script(<<~JS)
        (() => {
          const sys = (keyword, prop) => {
            const el = document.createElement("div")
            el.style.forcedColorAdjust = "none"
            el.style[prop] = keyword
            document.body.appendChild(el)
            const value = getComputedStyle(el)[prop]
            el.remove()
            return value
          }
          const style = getComputedStyle(document.querySelector(".sidebar-toggle--hide"))
          return {
            background: style.backgroundColor, color: style.color, border: style.borderTopColor,
            canvasText: sys("CanvasText", "color"), canvas: sys("Canvas", "color")
          }
        })()
      JS

      assert_equal probe["canvas"], probe["background"]
      assert_equal probe["canvasText"], probe["color"]
      assert_equal probe["canvasText"], probe["border"]
    end
  end
end
