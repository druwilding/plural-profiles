require "test_helper"

class Journal::EntriesControllerTest < ActionDispatch::IntegrationTest
  include FakeDreamwidthHelper

  setup do
    sign_in_as users(:one)
    @connection = journal_dreamwidth_connections(:one_main)
    FakeDreamwidthClient.add_journal("example_journal", api_key: [ "fakeKeyOneMain0001", "fakeKeyTwoShared0003" ])
    FakeDreamwidthClient.add_journal("second_journal", api_key: "fakeKeyOneSecond0002")
  end

  test "the header shows the journal's icon, its name, and a link to it on Dreamwidth" do
    FakeDreamwidthClient.journals["example_journal"][:entries] = [
      dreamwidth_entry(id: 1, icon_keyword: "(default)", icon_url: "https://v2.dreamwidth.org/7/1")
    ]

    get journal_dw_entries_path(@connection)

    assert_select ".card__header .journal-header__icon img[src=?][alt='']", "https://v2.dreamwidth.org/7/1"
    assert_select ".card__header h1", "example_journal's entries"
    assert_select ".card__header h1 + .journal-header__link a[href=?][target=_blank]", "https://example-journal.dreamwidth.org/"
  end

  test "with no icon to show, the header keeps an empty box" do
    get journal_dw_entries_path(@connection)

    assert_select ".card__header .journal-header__icon", 1
    assert_select ".card__header .journal-header__icon img", 0
  end

  test "lists the journal's entries, newest first" do
    FakeDreamwidthClient.journals["example_journal"][:entries] = [
      dreamwidth_entry(id: 1, subject: "Older one", datetime: "2026-10-01 09:00:00"),
      dreamwidth_entry(id: 2, subject: "", datetime: "2026-10-05 18:30:00")
    ]

    get journal_dw_entries_path(@connection)

    assert_response :success
    assert_select "h1", "example_journal's entries"
    assert_equal [ "(no subject)", "Older one" ], css_select(".journal-entry__subject").map(&:text)
    assert_select ".journal-entry__meta", /5 October 2026, 18:30/
    assert_select ".journal-entry__meta", /Private \(Just You\)/
    assert_select "a[href='https://example.dreamwidth.org/1.html']", /View on Dreamwidth\s*\(Older one\)/
  end

  test "in private-only mode, asks Dreamwidth for private entries only" do
    get journal_dw_entries_path(@connection)

    _method, _username, args = FakeDreamwidthClient.calls.find { |method, _username, _args| method == :entries }
    assert_equal "private", args[:security]
  end

  test "pages through with older and newer links" do
    per_page = Journal::EntriesController::PER_PAGE
    # Two full pages and five more, whatever the page size.
    FakeDreamwidthClient.journals["example_journal"][:entries] = (1..(per_page * 2) + 5).map do |id|
      dreamwidth_entry(id: id, datetime: (Time.utc(2026, 1, 1) + id.hours).strftime("%Y-%m-%d %H:%M:%S"))
    end

    get journal_dw_entries_path(@connection)
    assert_select ".journal-entry", per_page
    assert_select ".journal-pagination a[href=?]", journal_dw_entries_path(@connection, offset: per_page), text: /Older entries/
    assert_select ".journal-pagination a", text: /Newer entries/, count: 0

    get journal_dw_entries_path(@connection, offset: per_page * 2)
    assert_select ".journal-entry", 5
    assert_select ".journal-pagination a", text: /Older entries/, count: 0
    assert_select ".journal-pagination a", text: /Newer entries/
  end

  test "in the middle, it's older on the left, then newer on the right" do
    FakeDreamwidthClient.journals["example_journal"][:entries] = (1..45).map do |id|
      dreamwidth_entry(id: id, datetime: (Time.utc(2026, 1, 1) + id.hours).strftime("%Y-%m-%d %H:%M:%S"))
    end
    per_page = Journal::EntriesController::PER_PAGE
    get journal_dw_entries_path(@connection, offset: per_page)

    assert_equal [ "< Older entries", "Newer entries >" ],
      css_select(".journal-pagination > *").map { |part| part.text.squish }
    assert_select ".journal-pagination a:last-child.journal-pagination__newer"
    assert_equal [ "Older entries", "Newer entries" ],
      css_select(".journal-pagination a").map { |link| link.children.reject { |node| node["aria-hidden"] }.map(&:text).join.squish }
  end

  test "a hyphenated username in the URL finds the same journal" do
    get journal_dw_entries_path("Example-Journal")
    assert_response :success
  end

  test "someone else's journal, or one not connected, is a 404" do
    sign_in_as users(:three)
    get journal_dw_entries_path("example_journal")
    assert_response :not_found

    get journal_dw_entries_path("never_connected")
    assert_response :not_found
  end

  test "a key Dreamwidth stops accepting is recorded and explained" do
    FakeDreamwidthClient.fail_with(Dreamwidth::Client::KeyRejected)

    get journal_dw_entries_path(@connection)

    assert_response :success
    assert @connection.reload.failed?
    assert_select ".flash--warning", /stopped accepting the key/
    assert_select ".flash--warning a[href=?]", journal_dw_connection_path(@connection)
  end

  test "a successful list clears an earlier failure" do
    @connection.record_failure!

    get journal_dw_entries_path(@connection)

    assert_not @connection.reload.failed?
  end

  test "Dreamwidth being unavailable is explained, and doesn't count against the key" do
    FakeDreamwidthClient.fail_with(Dreamwidth::Client::Unavailable)

    get journal_dw_entries_path(@connection)

    assert_select ".flash--warning", /Couldn't reach Dreamwidth/
    assert_select ".card .flash--warning", 0, "problems sit above the pane, like flash messages"
    assert_not @connection.reload.failed?
  end

  test "there's no journal switcher on the entries page" do
    get journal_dw_entries_path(@connection)

    assert_select ".your-journals", 0
  end

  test "Manage has the journal switcher, listing every connected journal and marking this one" do
    get journal_dw_connection_path(@connection)

    assert_select ".your-journals a", 2
    assert_select ".your-journals a[aria-current='page']", "example_journal"
  end

  test "the journal links to itself on Dreamwidth, with hyphens" do
    sign_in_as users(:one)
    @connection.update!(username: "with_underscore")
    FakeDreamwidthClient.add_journal("with_underscore", api_key: "fakeKeyOneMain0001")

    get journal_dw_entries_path(@connection)

    assert_select "a.dreamwidth-journal-link[href='https://with-underscore.dreamwidth.org/'] strong", "with_underscore"
  end

  test "the userhead icon is our own copy, not loaded from Dreamwidth" do
    get journal_dw_entries_path(@connection)

    assert_select "img.dreamwidth-journal-link__userhead[src^='/assets/dreamwidth/user-'][alt='']"
    assert_select "img[src*='dreamwidth.org']", 0
  end

  test "every link to Dreamwidth opens in a new tab and says so" do
    FakeDreamwidthClient.journals["example_journal"][:entries] = [ dreamwidth_entry(id: 1) ]

    [ journal_dw_entries_path(@connection), journal_dw_connection_path(@connection), journal_connect_path ].each do |path|
      get path
      links = css_select("a[href*='dreamwidth.org']")
      assert links.any?, "#{path} should link to Dreamwidth"
      links.each do |link|
        assert_equal "_blank", link["target"], "#{link['href']} on #{path}"
        assert_match(/opens in a new tab/, link.text, "#{link['href']} on #{path}")
      end
    end
  end

  test "pages and links on journal pages don't prefetch" do
    get journal_dw_entries_path(@connection)

    assert_select "meta[name='turbo-prefetch'][content='false']"
  end
end
