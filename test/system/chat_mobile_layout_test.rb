require "application_system_test_case"

# The chat view on a phone: exactly the visible screen, with only the message
# history scrolling, and the newest messages kept in view when the keyboard
# opens and the page shrinks above it.
class ChatMobileLayoutTest < ApplicationSystemTestCase
  setup do
    @port = Capybara.current_session.server.port
    Capybara.app_host = "http://lvh.me:#{@port}"

    @owner = users(:one)
    @server = @owner.owned_chat_servers.create!(name: "Phone Server")
    @server.memberships.create!(user: @owner, role: "owner", default_postable: profiles(:alice))
    @channel = @server.channels.create!(name: "general")
    30.times do |i|
      @channel.messages.create!(user: @owner, postable: profiles(:alice), postable_name: "Alice", body: "Message number #{i + 1}")
    end
  end

  teardown do
    Capybara.app_host = nil
    # The browser is shared with later tests
    page.driver.browser.manage.window.resize_to(1400, 900)
  end

  test "the page is never taller than the screen, so the header and composer stay in view" do
    sign_in_via_browser(@owner)
    page.driver.browser.manage.window.resize_to(500, 800)
    visit chat_url

    # A phone's 100vh is the screen with the browser's bars hidden, taller
    # than what's visible while they show, which desktop Chrome can't
    # reproduce. The shared body rule's min-height: 100vh is what made the
    # page that tall, so check it's gone.
    assert_equal "0px", page.evaluate_script("getComputedStyle(document.body).minHeight")
    assert page.evaluate_script("document.scrollingElement.scrollHeight <= window.innerHeight"),
      "the page itself shouldn't scroll, only the message history"
  end

  test "the newest message stays in view when the keyboard takes space from the bottom" do
    sign_in_via_browser(@owner)
    page.driver.browser.manage.window.resize_to(500, 900)
    visit chat_url
    assert_text "Message number 30"
    assert newest_message_in_view?

    # As when the keyboard opens: the page shrinks to the space above it
    page.driver.browser.manage.window.resize_to(500, 500)

    assert_eventually { newest_message_in_view? }
  end

  test "someone reading older messages isn't moved when the pane changes size" do
    sign_in_via_browser(@owner)
    page.driver.browser.manage.window.resize_to(500, 900)
    visit chat_url
    assert_text "Message number 30"
    page.execute_script("document.querySelector('.chat-messages-scroll').scrollTop = 0")
    sleep 0.3

    page.driver.browser.manage.window.resize_to(500, 500)
    sleep 0.3

    assert_equal 0, page.evaluate_script("document.querySelector('.chat-messages-scroll').scrollTop")
  end

  private

  def chat_url
    "http://chat.lvh.me:#{@port}/servers/#{@server.uuid}/channels/#{@channel.uuid}"
  end

  # Its bottom edge isn't below the bottom of the history pane
  def newest_message_in_view?
    page.evaluate_script(<<~JS)
      (() => {
        const pane = document.querySelector(".chat-messages-scroll").getBoundingClientRect()
        const messages = document.querySelectorAll("#chat-messages .chat-message")
        const newest = messages[messages.length - 1].getBoundingClientRect()
        return newest.bottom <= pane.bottom + 1
      })()
    JS
  end

  def assert_eventually(timeout: Capybara.default_max_wait_time)
    deadline = Time.now + timeout
    sleep 0.1 until yield || Time.now > deadline
    assert yield
  end
end
