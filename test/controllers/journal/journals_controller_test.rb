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
    assert_select ".journal-list__item", 2
    assert_select "a[href=?]", journal_dw_entries_path("example_journal")
    assert_select "a[href=?]", journal_dw_entries_path("second_journal")
    assert_select "a", text: "Connect another Dreamwidth journal"
  end

  test "with no journals, explains and links straight to connecting one" do
    sign_in_as users(:three)
    get journal_root_path

    assert_select ".journal-list", 0
    assert_select "a[href=?]", journal_connect_path, text: "Connect a Dreamwidth journal"
  end

  test "a journal whose key stopped working says so" do
    sign_in_as users(:one)
    journal_dreamwidth_connections(:one_main).record_failure!

    get journal_root_path

    assert_select ".journal-list__problem", 1
  end

  test "the nav's Journal link is marked current on journal pages, and doesn't prefetch" do
    sign_in_as users(:one)
    get journal_root_path

    assert_select ".site-header nav a[href=?][aria-current='page'][data-turbo-prefetch='false']", journal_root_path
  end

  test "notices appear after the heading" do
    sign_in_as users(:one)
    delete journal_dw_connection_path("second_journal")
    follow_redirect!

    assert_select "main > .flash", 0
    assert_select ".card__header + .flash--notice", /Disconnected second_journal/
  end
end
