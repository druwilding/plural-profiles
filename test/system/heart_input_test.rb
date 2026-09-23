require "application_system_test_case"

# The heart picker button and the :ab heart autocomplete menu that
# ApplicationHelper#heart_field / heart_input_controller.js add to every field
# that renders heart codes.
class HeartInputTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @profile = profiles(:alice)
    sign_in_via_browser
  end

  def heart_button_for(field)
    field.find(:xpath, "..").find("button.heart-input__button")
  end

  def menu_for(field)
    field.find(:xpath, "..").find(".heart-input__menu", visible: :all)
  end

  def option_labels(field)
    menu_for(field).all("[role='option']").map(&:text)
  end

  def place_caret(field_id, position)
    page.execute_script(<<~JS, field_id, position)
      const field = document.getElementById(arguments[0])
      field.focus()
      field.setSelectionRange(arguments[1], arguments[1])
    JS
  end

  # -- Picker button and dialog --

  test "every heart-capable field on the profile form has a heart button" do
    visit edit_our_profile_path(@profile)

    %w[profile_name profile_subtitle profile_pronouns profile_tag_line profile_description].each do |id|
      assert heart_button_for(find("##{id}")).visible?, "expected a heart button on ##{id}"
    end
    assert_no_selector "#profile_labels_text + .heart-input__button"
  end

  test "the heart button inserts the chosen heart at the caret and it saves as the plain code" do
    visit edit_our_profile_path(@profile)
    field = find_field("Subtitle")
    field.fill_in with: "hello world"
    place_caret("profile_subtitle", 6)

    heart_button_for(field).click
    within("dialog.heart-dialog[open]") { click_button "abyss heart" }

    assert_no_selector "dialog.heart-dialog[open]"
    assert_field "Subtitle", with: "hello :abyss_heart: world"
    assert_selector "#profile_subtitle:focus"

    click_button "Update profile"
    assert_text "Profile updated."
    assert_equal "hello :abyss_heart: world", @profile.reload.subtitle
    assert_selector ".subtitle img.heart-inline[alt='abyss heart']"
  end

  test "the heart button appends to a field that hasn't been focused yet" do
    visit edit_our_profile_path(@profile)
    field = find_field("Tag line")

    heart_button_for(field).click
    within("dialog.heart-dialog[open]") { click_button "red heart" }

    assert_field "Tag line", with: "Always stargazing:red_heart: "
  end

  test "searching the picker filters hearts and Enter picks the first match" do
    visit edit_our_profile_path(@profile)
    field = find_field("Pronouns")
    field.fill_in with: ""

    heart_button_for(field).click
    within("dialog.heart-dialog[open]") do
      find(".heart-dialog__search").send_keys("ha")
      assert_equal [ "haunted heart", "shadow heart" ], all(".heart-dialog__heart").map { |button| button[:title] }
      find(".heart-dialog__search").send_keys(:enter)
    end

    assert_field "Pronouns", with: ":haunted_heart: "
  end

  test "closing the picker with Escape inserts nothing and returns focus to the field" do
    visit edit_our_profile_path(@profile)
    field = find_field("Subtitle")
    field.fill_in with: "unchanged"

    heart_button_for(field).click
    assert_selector "dialog.heart-dialog[open]"
    find(".heart-dialog__search").send_keys(:escape)

    assert_no_selector "dialog.heart-dialog[open]"
    assert_equal "unchanged", field.value
    assert_selector "#profile_subtitle:focus"
  end

  test "in forced colors the heart button and focus rings use the text colour" do
    visit edit_our_profile_path(@profile)

    with_forced_colors do
      canvas_text = page.evaluate_script(<<~JS)
        (() => {
          const el = document.createElement("div")
          el.style.forcedColorAdjust = "none"
          el.style.color = "CanvasText"
          document.body.appendChild(el)
          const value = getComputedStyle(el).color
          el.remove()
          return value
        })()
      JS

      find_field("Name").send_keys(:tab)
      assert_selector "#profile_name + .heart-input__button:focus-visible"
      button = page.evaluate_script(<<~JS)
        (() => {
          const style = getComputedStyle(document.activeElement)
          return { color: style.color, outlineColor: style.outlineColor, outlineStyle: style.outlineStyle }
        })()
      JS
      assert_equal canvas_text, button["color"], "the heart icon should be CanvasText"
      assert_equal canvas_text, button["outlineColor"], "the heart button focus ring should be CanvasText"
      assert_equal "solid", button["outlineStyle"]

      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "dialog.heart-dialog[open]"
      find(".heart-dialog__search").send_keys(:down)
      assert_selector ".heart-dialog__heart:focus-visible"
      heart_outline = page.evaluate_script("getComputedStyle(document.activeElement).outlineColor")
      assert_equal canvas_text, heart_outline, "a focused heart in the picker should be outlined in CanvasText"
    end
  end

  test "in forced colors the picker's buttons use system colours, not the theme's" do
    visit edit_our_profile_path(@profile)
    heart_button_for(find_field("Subtitle")).click
    assert_selector "dialog.heart-dialog[open]"

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
          const cs = selector => getComputedStyle(document.querySelector(selector))
          return {
            canvas: sys("Canvas", "backgroundColor"),
            canvasText: sys("CanvasText", "color"),
            heartColor: cs(".heart-dialog__heart-name").color,
            heartBg: cs(".heart-dialog__heart").backgroundColor,
            closeColor: cs(".heart-dialog__close").color,
            closeBg: cs(".heart-dialog__close").backgroundColor
          }
        })()
      JS

      assert_equal probe["canvasText"], probe["heartColor"], "heart names in the picker should be CanvasText"
      assert_equal probe["canvas"], probe["heartBg"], "hearts in the picker should sit on Canvas"
      assert_equal probe["canvasText"], probe["closeColor"], "the close button should be CanvasText"
      assert_equal probe["canvas"], probe["closeBg"], "the close button should sit on Canvas"
    end
  end

  # -- Autocomplete --

  test "typing a semicolon and two letters suggests starts-with matches first, then contains matches" do
    visit edit_our_profile_path(@profile)
    field = find_field("Subtitle")
    field.fill_in with: ""
    field.send_keys(";ab")

    assert_selector ".heart-input__option--active", text: "abyss heart"
    assert_equal [ "abyss heart", "vulnerable heart" ], option_labels(field)
    assert_equal "true", field[:"aria-expanded"]
    assert_images = menu_for(field).all("img").map { |img| URI(img[:src]).path }
    assert_equal [ HeartEmoji.image_path("abyss_heart"), HeartEmoji.image_path("vulnerable_heart") ], assert_images

    field.send_keys(:enter)

    assert_equal ":abyss_heart: ", field.value
    assert_no_selector ".heart-input__menu[role='listbox']", visible: true
    assert_current_path edit_our_profile_path(@profile), ignore_query: true
  end

  test "arrow keys move the highlight and Enter inserts that heart" do
    visit edit_our_profile_path(@profile)
    field = find_field("Subtitle")
    field.fill_in with: ""
    field.send_keys(";ab", :down)

    assert_selector ".heart-input__option--active", text: "vulnerable heart"
    field.send_keys(:enter)

    assert_equal ":vulnerable_heart: ", field.value
  end

  test "Tab also inserts the highlighted heart, and up wraps to the last option" do
    visit edit_our_profile_path(@profile)
    field = find_field("Subtitle")
    field.fill_in with: "so "
    field.send_keys(":ab", :up, :tab)

    assert_equal "so :vulnerable_heart: ", field.value
    assert_selector "#profile_subtitle:focus"
  end

  test "suggestions keep the heart list order within each group" do
    visit edit_our_profile_path(@profile)
    field = find_field("Subtitle")
    field.fill_in with: ""
    field.send_keys(":un")

    assert_selector ".heart-input__option--active", text: "hunter heart"
    assert_equal [ "hunter heart", "haunted heart", "burgundy heart", "hungry heart", "sunlit heart", "sunshine heart" ], option_labels(field)
  end

  test "the menu filters as more is typed and closes when the code is finished" do
    visit edit_our_profile_path(@profile)
    field = find_field("Subtitle")
    field.fill_in with: ""
    field.send_keys(":ha")
    assert_equal [ "haunted heart", "shadow heart" ], option_labels(field)

    field.send_keys("d")
    assert_selector ".heart-input__option", count: 1, text: "shadow heart"

    field.send_keys("ow_heart:")
    assert_no_selector ".heart-input__menu", visible: true
  end

  test "Escape dismisses the menu until what's typed changes" do
    visit edit_our_profile_path(@profile)
    field = find_field("Subtitle")
    field.fill_in with: ""
    field.send_keys(";ab")
    assert_selector ".heart-input__menu", visible: true

    field.send_keys(:escape)
    assert_no_selector ".heart-input__menu", visible: true
    assert_equal ";ab", field.value

    field.send_keys(:left, :right)
    assert_no_selector ".heart-input__menu", visible: true

    field.send_keys("y")
    assert_selector ".heart-input__option--active", text: "abyss heart"
  end

  test "hearts can be autocompleted straight after another heart code" do
    visit edit_our_profile_path(@profile)
    field = find_field("Subtitle")
    field.fill_in with: ""
    field.send_keys(":red_heart::ab")

    assert_selector ".heart-input__option--active", text: "abyss heart"
  end

  test "colons in ordinary text don't open the menu" do
    visit edit_our_profile_path(@profile)
    field = find_field("Subtitle")

    [ "at 10:30", "note:about", "https://abyss", "::ab", ";)" ].each do |text|
      field.fill_in with: ""
      field.send_keys(text)
      assert_no_selector ".heart-input__menu", visible: true, wait: 0.3
    end
  end

  test "autocomplete works on a later line of a textarea and opens near the caret" do
    visit edit_our_profile_path(@profile)
    field = find_field("Description")
    field.fill_in with: "line one\nline two "
    field.send_keys(:end, :control, :end) # caret to the very end
    field.send_keys(";ab")

    assert_selector ".heart-input__option--active", text: "abyss heart"
    menu_top, field_top, field_bottom = page.evaluate_script(<<~JS)
      (() => {
        const field = document.getElementById("profile_description").getBoundingClientRect()
        const menu = document.querySelector("#profile_description ~ .heart-input__menu").getBoundingClientRect()
        return [menu.top, field.top, field.bottom]
      })()
    JS
    assert menu_top > field_top, "expected the menu below the caret line"
    assert menu_top < field_top + (field_bottom - field_top) / 2, "expected the menu near the caret, not below the whole textarea"

    field.send_keys(:enter)
    assert_equal "line one\nline two :abyss_heart: ", field.value
  end

  test "group form fields get the heart button and autocomplete too" do
    visit edit_our_group_path(groups(:friends))
    field = find_field("Subtitle")
    assert heart_button_for(field).visible?

    field.fill_in with: ""
    field.send_keys(";ab", :enter)
    assert_equal ":abyss_heart: ", field.value
  end

  # -- Edge cases --

  test "the menu waits for an IME composition to finish" do
    visit edit_our_profile_path(@profile)
    page.execute_script(<<~JS)
      const field = document.getElementById("profile_subtitle")
      field.focus()
      field.value = ";ab"
      field.setSelectionRange(3, 3)
      field.dispatchEvent(new InputEvent("input", { bubbles: true, isComposing: true }))
    JS
    assert_no_selector ".heart-input__menu", visible: true, wait: 0.3

    page.execute_script(<<~JS)
      document.getElementById("profile_subtitle").dispatchEvent(new CompositionEvent("compositionend", { bubbles: true, data: "ab" }))
    JS
    assert_selector ".heart-input__option--active", text: "abyss heart"
  end

  test "going back to a page doesn't restore a duplicate picker dialog from the Turbo cache" do
    visit edit_our_profile_path(@profile)
    heart_button_for(find_field("Subtitle")).click
    find(".heart-dialog__search").send_keys(:escape)
    assert_no_selector "dialog.heart-dialog[open]"

    click_link "Cancel"
    assert_current_path our_profile_path(@profile)
    page.go_back
    assert_current_path edit_our_profile_path(@profile)

    heart_button_for(find_field("Subtitle")).click
    assert_selector "dialog.heart-dialog[open]"
    assert_equal 1, page.evaluate_script(%(document.querySelectorAll(".heart-dialog").length))
    assert_equal 1, page.evaluate_script(%(document.querySelectorAll("#heart-dialog-search").length))
  end

  test "a field that failed validation keeps room for the heart button" do
    visit edit_our_profile_path(@profile)
    page.execute_script(%(document.getElementById("profile_name").removeAttribute("required")))
    find_field("Name").fill_in with: ""
    click_button "Update profile"

    assert_selector ".field_with_errors > #profile_name"
    name_padding, subtitle_padding = page.evaluate_script(<<~JS)
      [ "profile_name", "profile_subtitle" ].map((id) => getComputedStyle(document.getElementById(id)).paddingRight)
    JS
    assert_equal subtitle_padding, name_padding
  end
end
