require "test_helper"

class Journal::ConnectionsControllerTest < ActionDispatch::IntegrationTest
  include FakeDreamwidthHelper

  setup do
    @user = users(:three)
    sign_in_as @user
    FakeDreamwidthClient.add_journal("new_journal", api_key: "goodKey123")
    FakeDreamwidthClient.add_journal("someone_else", api_key: "otherKey456")
  end

  def connect(username: "new_journal", api_key: "goodKey123")
    post journal_connect_path, params: { connection: { username: username, api_key: api_key } }
  end

  test "requires signing in" do
    sign_out
    get journal_connect_path
    assert_redirected_to new_session_path
  end

  test "a button beside Connect goes back to your journals" do
    get journal_connect_path

    assert_select "input[type=submit][value=Connect] + a.btn.btn--secondary[href=?]", journal_root_path,
      text: "Back to your journals"
  end

  test "connect page links to Dreamwidth's key page in a new tab" do
    get journal_connect_path

    assert_response :success
    assert_select "h1", "Connect a Dreamwidth journal"
    assert_select "a[href='https://www.dreamwidth.org/api/getkey'][target='_blank'][rel='noopener']", text: /opens in a new tab/
  end

  test "connecting with the journal's own key saves it, checked, and goes to its entries" do
    assert_difference -> { @user.dreamwidth_connections.count }, 1 do
      connect(username: "New-Journal")
    end

    connection = @user.dreamwidth_connections.last
    assert_equal "new_journal", connection.username
    assert_equal "goodKey123", connection.api_key
    assert connection.verified_at.present?
    assert_redirected_to journal_dw_entries_path("new_journal")
  end

  test "a key Dreamwidth doesn't accept isn't saved" do
    assert_no_difference -> { Journal::DreamwidthConnection.count } do
      connect(api_key: "wrongKey")
    end

    assert_response :unprocessable_entity
    assert_select "#connection-problem", /didn't accept that key/
  end

  test "another account's key is caught by the ownership check" do
    connect(api_key: "otherKey456")

    assert_response :unprocessable_entity
    assert_select "#connection-problem", /belongs to a different Dreamwidth account than\s+new_journal/
    assert_equal [ :access_lists, "new_journal" ], FakeDreamwidthClient.calls.last.first(2)
  end

  test "a journal Dreamwidth doesn't have" do
    connect(username: "no_such_journal")

    assert_response :unprocessable_entity
    assert_select "#connection-problem", /doesn't have an account called\s+no_such_journal/
  end

  test "Dreamwidth being unavailable saves nothing and says so" do
    FakeDreamwidthClient.fail_with(Dreamwidth::Client::Unavailable)

    assert_no_difference -> { Journal::DreamwidthConnection.count } do
      connect
    end
    assert_select "#connection-problem", /Couldn't reach Dreamwidth/
  end

  test "connecting a journal already connected links to managing it, without asking Dreamwidth" do
    sign_in_as users(:one)
    connect(username: "Example-Journal", api_key: "anything")

    assert_response :unprocessable_entity
    assert_select "#connection-problem", /already connected/
    assert_select "#connection-problem a[href=?]", journal_dw_connection_path("example_journal")
    assert_empty FakeDreamwidthClient.calls
  end

  test "a key already added for another journal names that journal" do
    sign_in_as users(:one)
    connect(username: "third_journal", api_key: "fakeKeyOneSecond0002")

    assert_response :unprocessable_entity
    assert_select "#connection-problem", /it's the one for\s+second_journal/
  end

  test "a username Dreamwidth couldn't have is refused before asking it" do
    connect(username: "no spaces allowed")

    assert_response :unprocessable_entity
    assert_select "#connection-problem", /Username must be/
    assert_empty FakeDreamwidthClient.calls
  end

  test "after a failure the username is kept and the key field is empty" do
    connect(api_key: "wrongKey")

    assert_select "input[name='connection[username]'][value='new_journal']"
    assert_select "input[name='connection[api_key]'][value='']"
    assert_not_includes response.body, "wrongKey"
  end

  test "the manage page shows the last four of the key, never the key" do
    sign_in_as users(:one)
    get journal_dw_connection_path("example_journal")

    assert_response :success
    assert_select "code", "********0001"
    assert_not_includes response.body, "fakeKeyOneMain0001"
  end

  test "the manage page has a button back to your journals" do
    sign_in_as users(:one)
    get journal_dw_connection_path("example_journal")

    assert_select "a.btn.btn--secondary[href=?]", journal_root_path, text: "Back to your journals"
  end

  test "someone else's journal, or one not connected, is a 404" do
    get journal_dw_connection_path("example_journal")
    assert_response :not_found

    get journal_dw_connection_path("never_connected")
    assert_response :not_found
  end

  test "replacing the key checks it and clears a failure" do
    sign_in_as users(:one)
    connection = journal_dreamwidth_connections(:one_main)
    connection.record_failure!
    FakeDreamwidthClient.add_journal("example_journal", api_key: "brandNewKey789")

    patch journal_dw_connection_path(connection), params: { connection: { api_key: "brandNewKey789" } }

    assert_redirected_to journal_dw_connection_path(connection)
    connection.reload
    assert_equal "brandNewKey789", connection.api_key
    assert_not connection.failed?
  end

  test "a replacement key Dreamwidth rejects leaves the old key in place" do
    sign_in_as users(:one)
    connection = journal_dreamwidth_connections(:one_main)
    FakeDreamwidthClient.add_journal("example_journal", api_key: "fakeKeyOneMain0001")

    patch journal_dw_connection_path(connection), params: { connection: { api_key: "wrongKey" } }

    assert_response :unprocessable_entity
    assert_select "#connection-problem", /didn't accept that key/
    assert_select "code", "********0001"
    assert_equal "fakeKeyOneMain0001", connection.reload.api_key
  end

  test "a replacement key already used for another journal names it" do
    sign_in_as users(:one)

    patch journal_dw_connection_path("example_journal"), params: { connection: { api_key: "fakeKeyOneSecond0002" } }

    assert_response :unprocessable_entity
    assert_select "#connection-problem", /it's the one for\s+second_journal/
  end

  test "disconnecting removes only that connection" do
    sign_in_as users(:one)

    assert_difference -> { Journal::DreamwidthConnection.count }, -1 do
      delete journal_dw_connection_path("example_journal")
    end
    assert_redirected_to journal_root_path
    assert journal_dreamwidth_connections(:two_shared).reload
  end
end
