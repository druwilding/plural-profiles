require "application_system_test_case"

# The composer's send button, and keeping a message from being sent twice:
# the box and button are disabled from sending until the page after it, with
# the message in it, arrives.
class ChatSendButtonTest < ApplicationSystemTestCase
  setup do
    @port = Capybara.current_session.server.port
    Capybara.app_host = "http://lvh.me:#{@port}"

    @owner = users(:one)
    @server = @owner.owned_chat_servers.create!(name: "Send Server")
    @server.memberships.create!(user: @owner, role: "owner", default_postable: profiles(:alice))
    @channel = @server.channels.create!(name: "general")
  end

  teardown do
    Capybara.app_host = nil
  end

  test "the send button sends the message" do
    sign_in_and_visit
    type "Sent with the button"
    click_button "Send"

    within("#chat-messages") { assert_text "Sent with the button" }
    assert_equal 1, @channel.messages.count
  end

  test "pressing Enter twice in quick succession sends the message once" do
    sign_in_and_visit
    type "Only once, please"
    composer.native.send_keys(:enter, :enter)

    within("#chat-messages") { assert_text "Only once, please" }
    # Give a second send time to land, if there was one
    sleep 1
    assert_equal 1, @channel.messages.count
  end

  test "clicking send twice in quick succession sends the message once" do
    sign_in_and_visit
    type "Double click"
    find("button.composer-send").double_click

    within("#chat-messages") { assert_text "Double click" }
    sleep 1
    assert_equal 1, @channel.messages.count
  end

  test "the box and button are disabled while the message is on its way" do
    sign_in_and_visit
    hold_back_sends
    type "Taking its time"
    click_button "Send"

    assert_selector "textarea[data-composer-target='textarea']:disabled"
    assert_selector "button.composer-send:disabled"

    page.execute_script("window.releaseSend()")
    within("#chat-messages") { assert_text "Taking its time" }
    assert_selector "textarea[data-composer-target='textarea']:not(:disabled)"
    assert_selector "button.composer-send:not(:disabled)"
  end

  test "a send that fails without reaching the server hands the message back to try again" do
    sign_in_and_visit
    page.execute_script(<<~JS)
      const realFetch = window.fetch
      window.fetch = (input, init) => (init?.method || "GET").toUpperCase() === "POST"
        ? Promise.reject(new TypeError("Failed to fetch"))
        : realFetch(input, init)
    JS
    type "Try again"
    click_button "Send"

    assert_selector "textarea[data-composer-target='textarea']:not(:disabled)"
    assert_selector "button.composer-send:not(:disabled)"
    assert_equal "Try again", composer.value
    assert_equal 0, @channel.messages.count
  end

  private

  def sign_in_and_visit
    sign_in_via_browser(@owner)
    visit "http://chat.lvh.me:#{@port}/servers/#{@server.uuid}/channels/#{@channel.uuid}"
    assert_text "No messages yet. Say hello!"
  end

  def composer
    find("textarea[data-composer-target='textarea']")
  end

  def type(text)
    fill_in placeholder: "Message #general (Enter to send, Shift+Enter for a new line)", with: text
  end

  # The next send waits until window.releaseSend() is called
  def hold_back_sends
    page.execute_script(<<~JS)
      const realFetch = window.fetch
      let release
      const held = new Promise(resolve => { release = resolve })
      window.releaseSend = () => release()
      window.fetch = async (input, init) => {
        if ((init?.method || "GET").toUpperCase() === "POST") await held
        return realFetch(input, init)
      }
    JS
  end
end
