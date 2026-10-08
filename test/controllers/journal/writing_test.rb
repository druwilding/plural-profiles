require "test_helper"

class Journal::WritingTest < ActionDispatch::IntegrationTest
  include FakeDreamwidthHelper

  setup do
    sign_in_as users(:one)
    @connection = journal_dreamwidth_connections(:one_main)
    FakeDreamwidthClient.add_journal("example_journal", api_key: "fakeKeyOneMain0001",
      icons: [ dreamwidth_icon(id: 8, keywords: [ "bass", "Music" ]), dreamwidth_icon(id: 9, keywords: "apple") ],
      entries: [ dreamwidth_entry(id: 1, icon_keyword: "(default)", icon_url: "https://v2.dreamwidth.org/7/1") ])
  end

  def post_entry(**fields)
    now = "2026-10-08T14:05"
    defaults = { subject: "Hello", body: "Some <b>text</b>\n\nand more", tags: "one, two", icon: "", security: "private",
                 datetime_original: now, datetime_parts: { month: "October", day: "8", year: "2026", hour: "14", minute: "05" } }
    post journal_dw_entries_path(@connection), params: { entry: defaults.merge(fields) }
  end

  def posted
    FakeDreamwidthClient.calls.reverse.find { |method, _username, _args| method == :create_entry }&.last
  end

  test "the write page names the journal in its heading and on the button" do
    get journal_dw_new_entry_path(@connection)

    assert_response :success
    assert_select "h1", "New entry in example_journal"
    assert_select "input[type=submit][value='Post to: example_journal']"
  end

  test "it's all one pane, with the fields in Dreamwidth's order" do
    get journal_dw_new_entry_path(@connection)

    assert_select ".card", 1
    assert_equal [ "Post to", "Icon", "Subject", "Entry text", "Tags", "Show this entry to" ],
      css_select(".card label:not(.visually-hidden)").map { |label| label.text.strip }
  end

  test "icons are listed by keyword, (default) first, each with its image" do
    get journal_dw_new_entry_path(@connection)

    assert_equal [ "(default)", "apple", "bass", "Music" ], css_select("select#entry_icon option").map(&:text)
    assert_select "select#entry_icon option[value='bass'][data-url='https://v2.dreamwidth.org/8/1']"
  end

  test "the default icon's image comes from the newest entry posted with (default)" do
    get journal_dw_new_entry_path(@connection)

    assert_select "img.journal-details__icon-image[src='https://v2.dreamwidth.org/7/1']"
  end

  test "Post to offers only the journal for now, and says communities will come" do
    get journal_dw_new_entry_path(@connection)

    assert_equal [ "example_journal" ], css_select("select#entry_post_to option").map(&:text)
    assert_select "select#entry_post_to:not([name])"
    assert_select "#post-to-hint", /communities will come later/
  end

  test "in private-only mode, Show this entry to offers only private" do
    get journal_dw_new_entry_path(@connection)

    assert_equal [ "Private (Just You)" ], css_select("select#entry_security option").map(&:text)
  end

  test "the date fields start at now, in the person's time zone" do
    users(:one).update!(time_zone: "Tokyo")

    travel_to Time.utc(2026, 10, 8, 23, 30) do
      get journal_dw_new_entry_path(@connection)
    end

    assert_select "select#datetime_day option[selected]", "9"
    assert_select "select#datetime_hour option[selected]", "08"
    assert_select "input[name='entry[datetime_original]'][value='2026-10-09T08:30']"
  end

  test "posting sends Dreamwidth what was written and lands on the entry" do
    users(:one).update!(time_zone: "Copenhagen")
    travel_to(Time.utc(2026, 10, 8, 16, 51)) { post_entry }

    assert_equal({ subject: "Hello", text: "Some <b>text</b>\n\nand more", security: "private", tags: [ "one", "two" ],
                   datetime: "2026-10-08 18:51" }, posted)
    entry_id = FakeDreamwidthClient.journals["example_journal"][:entries].last.id
    assert_redirected_to journal_dw_entry_path(@connection, entry_id)
  end

  test "a changed date and a chosen icon are sent" do
    post_entry(icon: "bass", datetime_parts: { month: "September", day: "30", year: "2026", hour: "09", minute: "15" })

    assert_equal "2026-09-30 09:15", posted[:datetime]
    assert_equal "bass", posted[:icon]
  end

  test "the entry page shows what Dreamwidth saved" do
    post_entry
    follow_redirect!

    assert_select "h1", "Entry in example_journal"
    assert_select ".flash--notice", "Your entry has been posted."
    assert_select "p", /only you can see it/
    assert_select "p strong", "Hello"
    assert_select "a[href=?]", journal_dw_new_entry_path(@connection), text: "Write another entry"
  end

  test "an entry with no subject says so" do
    post_entry(subject: "")
    follow_redirect!

    assert_select "p strong", "(no subject)"
  end

  test "empty entry text isn't sent, and the rest comes back" do
    post_entry(body: "  ", subject: "Keep me", tags: "keep, these")

    assert_response :unprocessable_entity
    assert_nil posted
    assert_select "#entry-problem", /Entry text can't be empty/
    assert_select "input[name='entry[subject]'][value='Keep me']"
    assert_select "input[name='entry[tags]'][value='keep, these']"
  end

  test "a tag that's too long isn't sent" do
    post_entry(tags: "fine, #{'x' * 41}")

    assert_response :unprocessable_entity
    assert_nil posted
    assert_select "#entry-problem", /up to 40 characters/
  end

  test "when Dreamwidth is unavailable, the writing comes back and it says nothing was posted" do
    FakeDreamwidthClient.fail_with(Dreamwidth::Client::Unavailable)
    post_entry

    assert_response :unprocessable_entity
    assert_select "#entry-problem", /nothing was posted/
    assert_select "textarea[name='entry[body]']", "Some <b>text</b>\n\nand more"
  end

  test "when Dreamwidth doesn't answer in time, it says to check before posting again" do
    FakeDreamwidthClient.fail_with(Dreamwidth::Client::TimedOut)
    post_entry

    assert_response :unprocessable_entity
    assert_select "#entry-problem", /isn't clear whether your entry was\s+posted/
    assert_select "#entry-problem a[href=?][target='_blank']", journal_dw_entries_path(@connection)
    assert_select "textarea[name='entry[body]']", "Some <b>text</b>\n\nand more"
  end

  test "Dreamwidth's own reason is passed on" do
    FakeDreamwidthClient.fail_with(Dreamwidth::Client::Invalid.new("Bad format for request body."))
    post_entry

    assert_select "#entry-problem", /Bad format for request body/
  end

  test "a rejected key is recorded and the writing comes back" do
    FakeDreamwidthClient.fail_with(Dreamwidth::Client::KeyRejected)
    post_entry

    assert_response :unprocessable_entity
    assert @connection.reload.failed?
    assert_select "textarea[name='entry[body]']", "Some <b>text</b>\n\nand more"
  end

  test "security other than private is refused in private-only mode" do
    skip "private-only mode is off" unless Journal::PRIVATE_ONLY
    post_entry(security: "public")

    assert_response :unprocessable_entity
    assert_nil posted
  end

  test "someone else's journal is a 404 for writing too" do
    sign_in_as users(:three)

    get journal_dw_new_entry_path("example_journal")
    assert_response :not_found
  end

  test "the entries page links to writing" do
    get journal_dw_entries_path(@connection)

    assert_select "a[href=?]", journal_dw_new_entry_path(@connection), text: "Write a new entry"
  end
end
