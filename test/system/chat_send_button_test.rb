require "application_system_test_case"

# The composer's send button, and keeping a message from being sent twice:
# from sending until the page after it, with the message in it, arrives, the
# box is read-only (keeping a phone's keyboard open) and the button disabled.
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

  test "the box is read-only and the button disabled while the message is on its way" do
    sign_in_and_visit
    hold_back_sends
    type "Taking its time"
    click_button "Send"

    assert_selector "textarea[data-composer-target='textarea'][readonly]"
    assert_selector "button.composer-send:disabled"

    page.execute_script("window.releaseSend()")
    within("#chat-messages") { assert_text "Taking its time" }
    assert_selector "textarea[data-composer-target='textarea']:not([readonly])"
    assert_selector "button.composer-send:not(:disabled)"
  end

  test "sending with Enter keeps the box focused, so a phone's keyboard stays open" do
    sign_in_and_visit
    hold_back_sends
    type "Keep typing after"
    composer.native.send_keys(:enter)

    assert_selector "textarea[data-composer-target='textarea'][readonly]"
    assert page.evaluate_script("document.activeElement.matches(\"textarea[data-composer-target='textarea']\")"),
      "a disabled box would lose focus, which closes a phone's keyboard"

    page.execute_script("window.releaseSend()")
    within("#chat-messages") { assert_text "Keep typing after" }
  end

  test "after sending, the same box is emptied and keeps focus, without reloading the page" do
    sign_in_and_visit
    # Gone if the page reloads or the box is replaced: a replaced box loses
    # focus, which closes a phone's keyboard until the new one takes it
    page.execute_script("document.body.dataset.notReloaded = 'true'")
    page.execute_script("document.querySelector(\"textarea[data-composer-target='textarea']\").dataset.sameBox = 'true'")
    type "Still typing"
    composer.native.send_keys(:enter)

    within("#chat-messages") { assert_text "Still typing" }
    assert_selector "textarea[data-same-box]:not([readonly])"
    assert_equal "", composer.value
    assert_selector "body[data-not-reloaded]"
    assert page.evaluate_script("document.activeElement.matches('textarea[data-same-box]')")

    # The send's answer and the live broadcast both carry it; it shows once
    sleep 1
    assert_selector "#chat-messages .chat-message", text: "Still typing", count: 1
    assert_no_text "No messages yet. Say hello!"
  end

  test "sending scrolls down to the new message, even from further up" do
    30.times { |i| @channel.messages.create!(user: @owner, postable: profiles(:alice), postable_name: "Alice", body: "Older #{i + 1}") }
    sign_in_and_visit(empty: false)
    page.execute_script("document.querySelector('.chat-messages-scroll').scrollTop = 0")
    type "Look at me"
    click_button "Send"

    within("#chat-messages") { assert_text "Look at me" }
    assert_eventually do
      page.evaluate_script(<<~JS)
        (() => {
          const pane = document.querySelector(".chat-messages-scroll").getBoundingClientRect()
          const messages = document.querySelectorAll("#chat-messages .chat-message")
          return messages[messages.length - 1].getBoundingClientRect().bottom <= pane.bottom + 1
        })()
      JS
    end
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

    assert_selector "textarea[data-composer-target='textarea']:not([readonly])"
    assert_selector "button.composer-send:not(:disabled)"
    assert_equal "Try again", composer.value
    assert_equal 0, @channel.messages.count
  end

  private

  def sign_in_and_visit(empty: true)
    sign_in_via_browser(@owner)
    visit "http://chat.lvh.me:#{@port}/servers/#{@server.uuid}/channels/#{@channel.uuid}"
    empty ? assert_text("No messages yet. Say hello!") : assert_selector("#chat-messages .chat-message")
  end

  def assert_eventually(timeout: Capybara.default_max_wait_time)
    deadline = Time.now + timeout
    sleep 0.1 until yield || Time.now > deadline
    assert yield
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
