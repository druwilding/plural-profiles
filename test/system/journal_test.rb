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

  test "journal.css comes with journal pages and goes when leaving them" do
    sign_in_via_browser
    within(".site-header nav") { click_link "Journal" }
    assert_selector "h1", text: "Journal"
    assert_selector "link[rel='stylesheet'][href*='/journal-']", visible: false

    within(".site-header nav") { click_link "Themes" }
    assert_selector "h1", text: "Themes"
    assert_no_selector "link[rel='stylesheet'][href*='/journal-']", visible: false
  end

  test "the current journal and nav link stay marked in forced colours" do
    sign_in_via_browser
    visit journal_dw_entries_path("example_journal")
    assert_selector "h1", text: "example_journal's entries"

    with_forced_colors do
      [ ".your-journals a[aria-current='page']", ".site-header nav a[aria-current='page']" ].each do |selector|
        decoration = page.evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json})).textDecorationLine")
        assert_equal "underline", decoration, "#{selector} should be underlined"
      end
    end
  end
end
