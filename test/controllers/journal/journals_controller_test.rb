require "test_helper"

class Journal::JournalsControllerTest < ActionDispatch::IntegrationTest
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
    assert_select ".journal-tile", 2
    assert_select ".journal-tile a[href=?]", journal_dw_entries_path("example_journal"), text: "example_journal"
    assert_select ".journal-tile a[href=?]", journal_dw_entries_path("second_journal"), text: "second_journal"
    assert_select ".journal-tile a.btn[href=?]", journal_dw_connection_path("example_journal"), text: /Manage/
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

  test "journal pages load journal.css, and other pages don't" do
    sign_in_as users(:one)

    get journal_root_path
    assert_select "link[rel='stylesheet'][href*='/journal-'][data-turbo-track='dynamic']", 1

    get our_themes_path
    assert_select "link[rel='stylesheet'][href*='/journal-']", 0
    assert_select "link[rel='stylesheet'][href*='/application-']", 1
  end

  test "notices appear after the heading" do
    sign_in_as users(:one)
    delete journal_dw_connection_path("second_journal")
    follow_redirect!

    assert_select "main > .flash", 0
    assert_select ".card__header + .flash--notice", /Disconnected second_journal/
  end
end
