require "application_system_test_case"

# Unread dots that arrive live wait a moment before they show, so one that's
# cleared again straight away (reading the very channel it's for) never
# blinks on; and while any are showing, the tab says so with a dot in its
# favicon and title (chat_unread_controller.js).
class ChatUnreadTabTest < ApplicationSystemTestCase
  setup do
    @port = Capybara.current_session.server.port
    Capybara.app_host = "http://lvh.me:#{@port}"

    @owner = users(:one)
    @member = users(:two)
    @server = @owner.owned_chat_servers.create!(name: "Tab Server")
    @server.memberships.create!(user: @owner, role: "owner", default_postable: profiles(:alice))
    @server.memberships.create!(user: @member, role: "member", default_postable: profiles(:carol))
    @general = @server.channels.create!(name: "general")
    @off_topic = @server.channels.create!(name: "off-topic")
  end

  teardown do
    Capybara.app_host = nil
  end

  test "a new message elsewhere puts a dot in the tab's favicon and title, and reading it takes them away" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    assert_no_selector ".server-rail .unread-dot", visible: :all
    assert_not title.start_with?("• ")
    assert_equal "/logo.png", favicon_href

    post_as_member "Over here", @off_topic

    assert_selector ".server-rail .unread-dot"
    assert_eventually { title.start_with?("• ") }
    assert_eventually { favicon_href.start_with?("data:image/png") }

    within(".channel-pane") { click_link "off-topic" }
    assert_text "Over here"
    assert_eventually { !title.start_with?("• ") }
    assert_eventually { favicon_href == "/logo.png" }
  end

  test "a message in the channel being read never blinks a dot on, in the rail or the tab" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    record_any_unread_showing

    post_as_member "Right here", @general
    within("#chat-messages") { assert_text "Right here" }
    sleep 3

    assert_equal false, page.evaluate_script("window.sawUnread")
    assert_no_selector ".server-rail .unread-dot", visible: :all
  end

  test "a dot that arrives live waits before it shows, and one cleared within that never shows" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))

    stream_rail_dot(unread: true)
    assert_selector ".server-rail .unread-dot.unread-dot--pending", visible: :all
    stream_rail_dot(unread: false)
    sleep 2

    assert_no_selector ".server-rail .unread-dot", visible: :all
    assert_not title.start_with?("• ")

    stream_rail_dot(unread: true)
    assert_selector ".server-rail .unread-dot:not(.unread-dot--pending)", wait: 3
  end

  test "a dot that's already showing doesn't blink when it's replaced by another" do
    @off_topic.messages.create!(user: @member, postable: profiles(:carol), postable_name: "Carol", body: "unread")
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    assert_selector ".server-rail .unread-dot:not(.unread-dot--pending)"

    stream_rail_dot(unread: true)
    assert_selector ".server-rail .unread-dot:not(.unread-dot--pending)", wait: 0
    assert title.start_with?("• ")
  end

  private

  def chat_url(path)
    "http://chat.lvh.me:#{@port}#{path}"
  end

  def channel_path(channel)
    "/servers/#{@server.uuid}/channels/#{channel.uuid}"
  end

  def post_as_member(body, channel)
    channel.messages.create!(user: @member, postable: profiles(:carol), postable_name: "Carol", body: body)
  end

  def title
    page.evaluate_script("document.title")
  end

  def favicon_href
    page.evaluate_script("document.querySelector(\"link[rel~='icon'][type='image/png']\").getAttribute('href')")
  end

  # As the server's broadcast of this server's rail dot
  def stream_rail_dot(unread:)
    id = "server_#{@server.id}_rail_dot"
    dot = unread ? %(<span class="unread-dot unread-dot--rail"><span class="visually-hidden">(unread)</span></span>) : ""
    page.execute_script(<<~JS, %(<turbo-stream action="replace" target="#{id}"><template><span id="#{id}">#{dot}</span></template></turbo-stream>))
      Turbo.renderStreamMessage(arguments[0])
    JS
  end

  # window.sawUnread becomes true if a rail dot or the title's dot ever shows.
  # Checked on every change to the page, not on a timer: on a fast machine the
  # dot can come and go within a few milliseconds. (This watcher starts after
  # chat_unread_controller.js's, so sees each change after it has.)
  def record_any_unread_showing
    page.execute_script(<<~JS)
      window.sawUnread = false
      const check = () => {
        const dot = document.querySelector(".server-rail .unread-dot")
        if ((dot && getComputedStyle(dot).visibility !== "hidden") || document.title.startsWith("• ")) window.sawUnread = true
      }
      new MutationObserver(check).observe(document.documentElement, { childList: true, subtree: true, characterData: true })
      setInterval(check, 50)
    JS
  end

  def assert_eventually(timeout: Capybara.default_max_wait_time)
    deadline = Time.now + timeout
    sleep 0.1 until yield || Time.now > deadline
    assert yield
  end
end
