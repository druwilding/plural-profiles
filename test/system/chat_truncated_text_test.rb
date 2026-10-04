require "application_system_test_case"

# Names and channel details cut short with an ellipsis to save room can still
# be read in full without a mouse: a title tooltip only appears on hover.
class ChatTruncatedTextTest < ApplicationSystemTestCase
  LONG_DESCRIPTION = "a place to talk about anything at all, from the weather to the meaning of life, and everything in between"

  setup do
    @port = Capybara.current_session.server.port
    Capybara.app_host = "http://lvh.me:#{@port}"

    @owner = users(:one)
    @server = @owner.owned_chat_servers.create!(name: "Server")
    @server.memberships.create!(user: @owner, role: "owner", default_postable: profiles(:alice))
    @channel = @server.channels.create!(name: "general", subtitle: "general chat", description: LONG_DESCRIPTION)
    @long = @server.channels.create!(name: "winding through the mist on a long and lonely road")
  end

  teardown do
    Capybara.app_host = nil
    # The browser is shared with later tests
    page.driver.browser.manage.window.resize_to(1400, 900)
  end

  test "more shows a channel's subtitle and description in full, and less cuts them short again" do
    sign_in_via_browser(@owner)
    page.driver.browser.manage.window.resize_to(900, 800)
    visit chat_url("/servers/#{@server.uuid}/channels/#{@channel.uuid}")

    assert cut_short?(".chat-channel-header .description")
    click_button "more of the channel details"
    assert_selector "button[aria-expanded='true']", text: "less"
    assert_not cut_short?(".chat-channel-header .description")
    assert_text LONG_DESCRIPTION

    click_button "less of the channel details"
    assert_selector "button[aria-expanded='false']", text: "more"
    assert cut_short?(".chat-channel-header .description")
  end

  test "there's no more button when nothing is cut short" do
    @channel.update!(description: "short")
    sign_in_via_browser(@owner)
    visit chat_url("/servers/#{@server.uuid}/channels/#{@channel.uuid}")

    assert_selector ".chat-channel-header .description", text: "short"
    assert_no_button "more of the channel details"
  end

  test "the more button appears when the window gets too narrow for the details" do
    @channel.update!(description: "a place to talk")
    sign_in_via_browser(@owner)
    visit chat_url("/servers/#{@server.uuid}/channels/#{@channel.uuid}")
    assert_no_button "more of the channel details"

    page.driver.browser.manage.window.resize_to(700, 800)
    assert_button "more of the channel details"
  end

  test "a channel's name shows in full in the list while it has keyboard focus" do
    sign_in_via_browser(@owner)
    visit chat_url("/servers/#{@server.uuid}/channels/#{@channel.uuid}")
    name = ".channel-pane a[title='# #{@long.name}'] .channel-pane__name"
    assert cut_short?(name)

    # Tab from the channel before it, so the browser treats it as keyboard focus
    page.execute_script("document.querySelector(\".channel-pane a[title='# general']\").focus()")
    find(".channel-pane a[title='# general']").native.send_keys(:tab)

    assert_not cut_short?(name)
  end

  private

  def chat_url(path)
    "http://chat.lvh.me:#{@port}#{path}"
  end

  def cut_short?(selector)
    find(selector)
    page.evaluate_script("(el => el.scrollWidth > el.clientWidth)(document.querySelector(arguments[0]))", selector)
  end
end
