require "application_system_test_case"

class AdminEmotesTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_via_browser
    visit admin_emotes_path
  end

  def row_names
    all("#emote-sections .emote-section:not(.emote-section--archived) input[name='emote[name]']").map(&:value)
  end

  def name_field(emote)
    find_field(id: "name_#{ActionView::RecordIdentifier.dom_id(emote)}")
  end

  test "renaming on blur moves the row, shows the new code and keeps focus with it" do
    cadbury = emotes(:cadbury_heart)
    field = name_field(cadbury)
    field.fill_in with: "00_chocolate_heart"
    field.send_keys(:tab)

    assert_selector "#emote-status", text: "Saved 00_chocolate_heart."
    assert_equal "00_chocolate_heart", row_names.first
    within("##{ActionView::RecordIdentifier.dom_id(cadbury)}") do
      assert_field "Code", with: "chocolate_heart", disabled: true
      assert_selector ".emote-row__alias code", text: ":cadbury_heart:"
    end
    # Tab moved focus on to the code override checkbox before the re-render.
    assert_equal "code_overridden_#{ActionView::RecordIdentifier.dom_id(cadbury)}", evaluate_script("document.activeElement.id")
  end

  test "renaming with Enter keeps focus in the renamed field" do
    cadbury = emotes(:cadbury_heart)
    field = name_field(cadbury)
    field.fill_in with: "99_cadbury_heart"
    field.send_keys(:enter)

    assert_selector "#emote-status", text: "Saved 99_cadbury_heart."
    assert_equal "99_cadbury_heart", row_names.last
    assert_equal "name_#{ActionView::RecordIdentifier.dom_id(cadbury)}", evaluate_script("document.activeElement.id")
  end

  test "a clashing name shows an error on the row and saves nothing" do
    field = name_field(emotes(:cadbury_heart))
    field.fill_in with: "red_heart"
    field.send_keys(:enter)

    assert_selector ".emote-row__errors", text: "“red_heart” is already used by 36_red_heart"
    assert_equal "48_cadbury_heart", emotes(:cadbury_heart).reload.name
  end

  test "overriding a code" do
    cadbury = emotes(:cadbury_heart)
    within("##{ActionView::RecordIdentifier.dom_id(cadbury)}") do
      check "Custom code"
      assert_field "Code", with: "cadbury_heart", disabled: false
      fill_in "Code", with: "cadbury"
      find_field("Code").send_keys(:enter)
    end

    # The old code only becomes an alias once the new code is saved.
    within("##{ActionView::RecordIdentifier.dom_id(cadbury)}") do
      assert_selector ".emote-row__alias code", text: ":cadbury_heart:"
      assert_field "Code", with: "cadbury"
    end
    assert_equal "cadbury", cadbury.reload.code
  end

  test "filtering by name or code" do
    fill_in "Filter", with: ":cadbury"
    assert_equal [ "48_cadbury_heart" ], all(".emote-row", visible: true).map { |row| row.find("input[name='emote[name]']").value }
  end

  test "filtering opens collapsed groups with a match, and clearing it closes them again" do
    find("summary", text: "Hearts").click
    assert_selector "details.emote-section:not([open])", text: "Hearts"

    fill_in "Filter", with: ":cadbury"
    assert_selector "details.emote-section[open]", text: "Hearts"
    assert_field with: "48_cadbury_heart"

    fill_in "Filter", with: ""
    assert_selector "details.emote-section:not([open])", text: "Hearts"

    # The filter opening it wasn't remembered.
    visit admin_emotes_path
    assert_selector "details.emote-section:not([open])", text: "Hearts"
  end

  test "archiving and restoring" do
    red = emotes(:red_heart)
    find("a[aria-label='Archive 36_red_heart']").click

    assert_selector "#emote-status", text: "Archived 36_red_heart."
    assert_not_includes row_names, "36_red_heart"
    find("summary", text: "Archived").click
    within(".emote-section--archived") { find("a[aria-label='Restore 36_red_heart']").click }

    assert_selector "#emote-status", text: "Restored 36_red_heart."
    assert_includes row_names, "36_red_heart"
    assert_not red.reload.archived?
  end

  test "a collapsed group stays collapsed when the list re-renders" do
    find("a[aria-label='Archive 36_red_heart']").click
    assert_selector "#emote-status", text: "Archived 36_red_heart."

    find("summary", text: "Hearts").click
    assert_selector "details.emote-section:not([open])", text: "Hearts"

    find("summary", text: "Archived").click
    within(".emote-section--archived") { find("a[aria-label='Restore 36_red_heart']").click }

    assert_selector "#emote-status", text: "Restored 36_red_heart."
    assert_selector "details.emote-section:not([open])", text: "Hearts"
    assert_no_selector "input[name='emote[name]'][value='36_red_heart']"
  end
end
