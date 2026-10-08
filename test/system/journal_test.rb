require "application_system_test_case"

class JournalTest < ApplicationSystemTestCase
  include FakeDreamwidthHelper

  setup do
    @user = users(:one)
    FakeDreamwidthClient.add_journal("example_journal", api_key: "fakeKeyOneMain0001",
      entries: [ dreamwidth_entry(id: 1, subject: "Monday thoughts") ])
    FakeDreamwidthClient.add_journal("second_journal", api_key: "fakeKeyOneSecond0002",
      entries: [ dreamwidth_entry(id: 2, subject: "Second journal's entry") ])
    FakeDreamwidthClient.add_journal("brand_new", api_key: "brandNewKey123",
      entries: [ dreamwidth_entry(id: 3, subject: "Hello from the new one") ])
  end

  test "connect a journal from the nav, then see its entries" do
    sign_in_via_browser
    within(".site-header nav") { click_link "Journal" }
    click_link "Connect another Dreamwidth journal"

    fill_in "Dreamwidth username", with: "Brand-New"
    fill_in "API key", with: "brandNewKey123"
    click_button "Connect"

    assert_selector "h1", text: "brand_new's entries"
    assert_text "Connected brand_new."
    assert_text "Hello from the new one"
  end

  test "a wrong key keeps the username and explains" do
    sign_in_via_browser
    visit journal_connect_path

    fill_in "Dreamwidth username", with: "brand_new"
    fill_in "API key", with: "notTheKey"
    click_button "Connect"

    assert_selector "#connection-problem", text: "Dreamwidth didn't accept that key"
    assert_field "Dreamwidth username", with: "brand_new"
    assert_field "API key", with: ""
  end

  test "switching journals with the Your journals links" do
    sign_in_via_browser
    visit journal_dw_entries_path("example_journal")
    assert_selector "h1", text: "example_journal's entries"
    assert_text "Monday thoughts"

    within(".your-journals") { click_link "second_journal" }

    assert_selector "h1", text: "second_journal's entries"
    assert_text "Second journal's entry"
    assert_no_text "Monday thoughts"
    assert_selector ".your-journals a[aria-current='page']", text: "second_journal"
  end

  test "write a private entry, post it, and see what Dreamwidth saved" do
    sign_in_via_browser
    visit journal_dw_entries_path("example_journal")
    click_link "Post an Entry"

    assert_selector "h1", text: "Post an Entry"
    fill_in "Subject", with: "Tuesday thoughts"
    fill_in "Entry text", with: "First paragraph.\n\nSecond one."
    fill_in "Tags", with: "days, thoughts"
    click_button "Post to: example_journal"

    assert_selector "h1", text: "Entry in example_journal"
    assert_text "Your entry has been posted."
    assert_text "only you can see it"
    assert_selector "strong", text: "Tuesday thoughts"
    posted = FakeDreamwidthClient.journals["example_journal"][:entries].last
    assert_equal "First paragraph.\n\nSecond one.", posted.body
    assert_equal [ "days", "thoughts" ], posted.tags
  end

  test "coming back to write again doesn't flash up what was typed before" do
    sign_in_via_browser
    visit journal_dw_entries_path("example_journal")
    click_link "Post an Entry"
    assert_selector "h1", text: "Post an Entry"
    fill_in "Subject", with: "Half-written"
    fill_in "Entry text", with: "Not finished"
    click_link "Back to example_journal's entries"
    assert_selector "h1", text: "example_journal's entries"

    # A cached snapshot would be rendered first, as a preview, with the old
    # text in it; without one, the old text never appears.
    page.execute_script(<<~JS)
      window.sawOldText = false
      document.addEventListener("turbo:render", () => {
        const subject = document.getElementById("entry_subject")
        if (subject && subject.value === "Half-written") window.sawOldText = true
      })
    JS
    click_link "Post an Entry"

    assert_selector "h1", text: "Post an Entry"
    assert_field "Subject", with: ""
    assert_equal false, page.evaluate_script("window.sawOldText")
  end

  test "choosing an icon shows it straight away" do
    FakeDreamwidthClient.journals["example_journal"][:icons] = [ dreamwidth_icon(id: 8, keywords: "bass") ]
    sign_in_via_browser
    visit journal_dw_new_entry_path("example_journal")
    assert_selector "h1", text: "Post an Entry"
    assert_no_selector ".journal-details__icon-image", visible: true

    select "bass", from: "Icon"

    assert_selector ".journal-details__icon-image[src='https://v2.dreamwidth.org/8/1']", visible: :all
    assert_equal false, page.evaluate_script("document.querySelector('.journal-details__icon-image').hidden")
  end

  test "the spinner goes once the chosen icon has loaded, or failed to" do
    FakeDreamwidthClient.journals["example_journal"][:icons] = [ dreamwidth_icon(id: 8, keywords: "bass") ]
    sign_in_via_browser
    visit journal_dw_new_entry_path("example_journal")
    assert_selector "h1", text: "Post an Entry"

    # Dreamwidth is unreachable in browser tests, so the image fails at once.
    select "bass", from: "Icon"

    assert_no_selector ".journal-details__icon--loading"
    assert_selector ".journal-details__spinner", visible: :hidden
  end

  test "typing one character suggests every tag starting with it, and only those" do
    FakeDreamwidthClient.journals["example_journal"][:tags] = [ "*mood", "art", "days", "Diary", "Monday", "today" ]
    sign_in_via_browser
    visit journal_dw_new_entry_path("example_journal")
    assert_selector "h1", text: "Post an Entry"

    find_field("Tags").send_keys("d")

    assert_selector "[role='listbox'][aria-label='Matching tags']"
    assert_equal [ "days", "Diary" ], all("[role='option']").map(&:text)
    assert_selector "[role='option'][aria-selected='true']", text: "days"
    assert_equal "true", find_field("Tags")["aria-expanded"]
  end

  test "choosing a tag adds it with a comma, and it isn't suggested again" do
    FakeDreamwidthClient.journals["example_journal"][:tags] = [ "*mood", "days", "Monday" ]
    sign_in_via_browser
    visit journal_dw_new_entry_path("example_journal")
    assert_selector "h1", text: "Post an Entry"
    field = find_field("Tags")

    field.send_keys("*m", :enter)
    assert_field "Tags", with: "*mood, "
    assert_no_selector "[role='listbox']"

    field.send_keys("m", :down, :tab)
    assert_field "Tags", with: "*mood, Monday, "

    field.send_keys("o")
    assert_no_selector "[role='listbox']"
  end

  test "Enter in the tag list chooses rather than posting" do
    FakeDreamwidthClient.journals["example_journal"][:tags] = [ "days" ]
    sign_in_via_browser
    visit journal_dw_new_entry_path("example_journal")
    assert_selector "h1", text: "Post an Entry"
    fill_in "Entry text", with: "Hello"

    find_field("Tags").send_keys("da", :enter)

    assert_field "Tags", with: "days, "
    assert_selector "h1", text: "Post an Entry"
    assert_not FakeDreamwidthClient.calls.any? { |method, _username, _args| method == :create_entry }
  end

  test "Escape closes the tag list until something else is typed" do
    FakeDreamwidthClient.journals["example_journal"][:tags] = [ "days", "daisies" ]
    sign_in_via_browser
    visit journal_dw_new_entry_path("example_journal")
    assert_selector "h1", text: "Post an Entry"
    field = find_field("Tags")

    field.send_keys("d")
    assert_selector "[role='listbox']"
    field.send_keys(:escape)
    assert_no_selector "[role='listbox']"

    field.send_keys("a")
    assert_equal [ "daisies", "days" ].sort, all("[role='option']").map(&:text).sort
  end

  test "journal.css comes with journal pages and goes when leaving them" do
    sign_in_via_browser
    within(".site-header nav") { click_link "Journal" }
    assert_selector "h1", text: "Journal"
    assert_selector "link[rel='stylesheet'][href*='/journal-']", visible: false

    within(".site-header nav") { click_link "Themes" }
    assert_selector "h1", text: "Themes"
    assert_no_selector "link[rel='stylesheet'][href*='/journal-']", visible: false
  end

  test "the current journal stays marked in forced colours" do
    sign_in_via_browser
    visit journal_dw_entries_path("example_journal")
    assert_selector "h1", text: "example_journal's entries"

    with_forced_colors do
      decoration = page.evaluate_script(
        "getComputedStyle(document.querySelector(\".your-journals a[aria-current='page']\")).textDecorationLine"
      )
      assert_equal "underline", decoration
    end
  end
end
