require "test_helper"

class Journal::JournalsControllerTest < ActionDispatch::IntegrationTest
  include FakeDreamwidthHelper

  test "requires signing in" do
    get journal_root_path
    assert_redirected_to new_session_path
  end

  test "lists only your own journals" do
    sign_in_as users(:one)
    get journal_root_path

    assert_response :success
    assert_select "h1", "Your journals"
    assert_select "title", /\AYour journals/
    assert_select "p", /a way into Dreamwidth/
    assert_select "p", /The API keys are\s+encrypted/
    assert_select ".journal-tile", 2
    assert_select ".journal-tile a[href=?]", journal_dw_entries_path("example_journal"), text: "example_journal"
    assert_select ".journal-tile a[href=?]", journal_dw_entries_path("second_journal"), text: "second_journal"
    assert_select ".journal-tile__actions a.btn:not(.btn--secondary)[href=?]", journal_dw_new_entry_path("example_journal"),
      text: /Post\s+an entry to example_journal/
    assert_select ".journal-tile__actions a.btn.btn--secondary[href=?]", journal_dw_connection_path("example_journal"), text: /Manage/
    assert_select "a", text: "Connect another Dreamwidth journal"
  end

  test "with no journals, explains and links straight to connecting one" do
    sign_in_as users(:three)
    get journal_root_path

    assert_select ".journal-tiles", 0
    assert_select "a[href=?]", journal_connect_path, text: "Connect a Dreamwidth journal"
  end

  test "a journal whose key stopped working says so" do
    sign_in_as users(:one)
    journal_dreamwidth_connections(:one_main).record_failure!

    get journal_root_path

    assert_select ".journal-tile__problem", 1
  end

  test "each tile's icon loads after the page, so Dreamwidth isn't asked for the page itself" do
    sign_in_as users(:one)
    get journal_root_path

    assert_select "turbo-frame[src=?][loading=lazy]", journal_dw_icon_path("example_journal")
    assert_select "turbo-frame[src=?][loading=lazy]", journal_dw_icon_path("second_journal")
  end

  test "the nav's Journal link is marked current on journal pages, and doesn't prefetch" do
    sign_in_as users(:one)
    get journal_root_path

    assert_select ".site-header nav a[href=?][aria-current='page'][data-turbo-prefetch='false']", journal_root_path
  end

  test "journal pages neither prefetch nor show a cached snapshot, and other pages do" do
    sign_in_as users(:one)
    FakeDreamwidthClient.add_journal("example_journal", api_key: "fakeKeyOneMain0001")

    [ journal_root_path, journal_connect_path, journal_dw_entries_path("example_journal"),
      journal_dw_new_entry_path("example_journal"), journal_dw_connection_path("example_journal") ].each do |path|
      get path
      assert_select "meta[name='turbo-prefetch'][content='false']", 1, "prefetch on #{path}"
      assert_select "meta[name='turbo-cache-control'][content='no-cache']", 1, "cache on #{path}"
    end

    get our_themes_path
    assert_select "meta[name='turbo-cache-control']", 0
  end

  test "journal pages load journal.css, and other pages don't" do
    sign_in_as users(:one)

    get journal_root_path
    assert_select "link[rel='stylesheet'][href*='/journal-'][data-turbo-track='dynamic']", 1

    get our_themes_path
    assert_select "link[rel='stylesheet'][href*='/journal-']", 0
    assert_select "link[rel='stylesheet'][href*='/application-']", 1
  end

  test "notices appear above the pane, as elsewhere in pp" do
    sign_in_as users(:one)
    delete journal_dw_connection_path("second_journal")
    follow_redirect!

    assert_select "main > .flash--notice", /Disconnected second_journal/
    assert_select ".card .flash--notice", 0
  end
end
