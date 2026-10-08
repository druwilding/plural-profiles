require "test_helper"

class Journal::IconsControllerTest < ActionDispatch::IntegrationTest
  include FakeDreamwidthHelper

  setup do
    sign_in_as users(:one)
    @connection = journal_dreamwidth_connections(:one_main)
  end

  def icon_src
    css_select("turbo-frame##{ActionView::RecordIdentifier.dom_id(@connection, :icon)} img").first&.[]("src")
  end

  test "the default icon, from the newest entry posted with it" do
    FakeDreamwidthClient.add_journal("example_journal", api_key: "fakeKeyOneMain0001",
      icons: [ dreamwidth_icon(id: 8, keywords: "bass") ],
      entries: [ dreamwidth_entry(id: 1, icon_keyword: "(default)", icon_url: "https://v2.dreamwidth.org/7/1") ])

    get journal_dw_icon_path(@connection)

    assert_response :success
    assert_equal "https://v2.dreamwidth.org/7/1", icon_src
  end

  test "the first icon when no entry shows the default" do
    FakeDreamwidthClient.add_journal("example_journal", api_key: "fakeKeyOneMain0001",
      icons: [ dreamwidth_icon(id: 8, keywords: "bass"), dreamwidth_icon(id: 9, keywords: "apple") ])

    get journal_dw_icon_path(@connection)

    assert_equal "https://v2.dreamwidth.org/8/1", icon_src
  end

  test "no icons, or Dreamwidth unavailable, leaves the box empty" do
    FakeDreamwidthClient.add_journal("example_journal", api_key: "fakeKeyOneMain0001")
    get journal_dw_icon_path(@connection)
    assert_response :success
    assert_nil icon_src

    FakeDreamwidthClient.fail_with(Dreamwidth::Client::Unavailable)
    get journal_dw_icon_path(@connection)
    assert_response :success
    assert_nil icon_src
  end

  test "a rejected key is recorded" do
    FakeDreamwidthClient.add_journal("example_journal", api_key: "fakeKeyOneMain0001")
    FakeDreamwidthClient.fail_with(Dreamwidth::Client::KeyRejected)

    get journal_dw_icon_path(@connection)

    assert @connection.reload.failed?
  end

  test "someone else's journal is a 404" do
    sign_in_as users(:three)
    get journal_dw_icon_path("example_journal")
    assert_response :not_found
  end
end
