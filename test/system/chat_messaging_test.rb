require "application_system_test_case"

# Covers interactions that only show up once two members are involved: a
# live Action Cable broadcast landing in someone else's already-open browser
# tab, and the unread-dot bookkeeping that runs alongside it.
class ChatMessagingTest < ApplicationSystemTestCase
  setup do
    @port = Capybara.current_session.server.port
    Capybara.app_host = "http://lvh.me:#{@port}"

    @owner = users(:one)
    @member = users(:two)

    @server = @owner.owned_chat_servers.create!(name: "Live Server")
    @server.memberships.create!(user: @owner, role: "owner", default_postable: profiles(:alice))
    @server.memberships.create!(user: @member, role: "member", default_postable: profiles(:carol))
    @channel = @server.channels.create!(name: "general")
    @other_channel = @server.channels.create!(name: "off-topic")
  end

  teardown do
    Capybara.app_host = nil
  end

  def chat_url(path)
    "http://chat.lvh.me:#{@port}#{path}"
  end

  def channel_path(channel = @channel)
    "/servers/#{@server.uuid}/channels/#{channel.uuid}"
  end

  def send_message(text)
    fill_in placeholder: "Message ##{@channel.name} (Enter to send, Shift+Enter for a new line)", with: text
    find("textarea").native.send_keys(:enter)
  end

  test "a message posted by one member appears live for another member already viewing the channel" do
    using_session(:owner) do
      sign_in_via_browser(@owner)
      visit chat_url(channel_path)
      assert_text "No messages yet. Say hello!"
    end

    using_session(:member) do
      sign_in_via_browser(@member)
      visit chat_url(channel_path)
      send_message("Hi from Carol!")
      assert_text "Hi from Carol!"
    end

    using_session(:owner) do
      # No reload here — this only appears if the turbo_stream_from broadcast
      # (Chat::Message#broadcast_append_to) reached this open tab live.
      assert_text "Hi from Carol!"
      assert_text "Carol"
    end
  end

  test "a live message on a new day gets a date divider, but only the first" do
    using_session(:owner) do
      sign_in_via_browser(@owner)
      visit chat_url(channel_path)
      assert_text "No messages yet. Say hello!"
    end

    using_session(:member) do
      sign_in_via_browser(@member)
      visit chat_url(channel_path)
      send_message("First of the day")
      within("#chat-messages") { assert_text "First of the day" }
      send_message("Second of the day")
      within("#chat-messages") { assert_text "Second of the day" }
      assert_selector "#chat-messages .chat-date-divider", text: "TODAY", count: 1
    end

    using_session(:owner) do
      within("#chat-messages") { assert_text "Second of the day" }
      assert_selector "#chat-messages .chat-date-divider", text: "TODAY", count: 1
      assert_selector "#chat-messages .chat-date-divider + .chat-message", text: "First of the day"
    end
  end

  test "switching the posting-as profile changes whose name is attached to new messages" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path)

    assert_text "Posting as"
    assert_text profiles(:alice).name

    within(".composer-posting-as") do
      find(".profile-picker__trigger").click
      click_link profiles(:bob).name
    end

    # The profile switch link is a Turbo PATCH that turbo_stream-replaces just
    # the picker — wait for that to settle before typing.
    assert_selector ".profile-picker__trigger", text: profiles(:bob).name

    send_message("Switched over to Bob")

    within("#chat-messages") do
      assert_text "Switched over to Bob"
      assert_text profiles(:bob).name
      assert_no_text profiles(:alice).name
    end
  end

  test "switching the posting-as profile does not clear an in-progress message" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path)

    fill_in placeholder: "Message ##{@channel.name} (Enter to send, Shift+Enter for a new line)", with: "Don't lose this"

    within(".composer-posting-as") do
      find(".profile-picker__trigger").click
      click_link profiles(:bob).name
    end

    assert_selector ".profile-picker__trigger", text: profiles(:bob).name
    assert_equal "Don't lose this", find("textarea").value
  end

  test "switching the posting-as profile sticks after further typing with no proxy bracket match" do
    # Regression: the picker turbo_stream-replaces just the trigger, which
    # doesn't reconnect the composer controller — a stale connect()-time
    # cache of the "default" pill previously meant the very next keystroke
    # (finding no bracket match) reverted the pill back to whichever profile
    # was selected when the page first loaded, undoing the switch visually
    # even though the stored default really had changed.
    sign_in_via_browser(@owner)
    visit chat_url(channel_path)

    assert_text "Posting as"
    assert_selector ".profile-picker__trigger", text: profiles(:alice).name

    within(".composer-posting-as") do
      find(".profile-picker__trigger").click
      click_link profiles(:bob).name
    end
    assert_selector ".profile-picker__trigger", text: profiles(:bob).name

    fill_in placeholder: "Message ##{@channel.name} (Enter to send, Shift+Enter for a new line)", with: "just carrying on typing"

    assert_selector ".profile-picker__trigger", text: profiles(:bob).name
    assert_no_selector ".profile-picker__trigger", text: profiles(:alice).name
  end

  test "typing a profile's chat proxy brackets posts as that profile instead of the default" do
    profiles(:bob).update!(chat_bracket_before: "bob:")

    sign_in_via_browser(@owner)
    visit chat_url(channel_path)

    send_message("bob: borrowed the mic")

    within("#chat-messages") do
      assert_text "borrowed the mic"
      assert_text profiles(:bob).name
      assert_no_text "bob:" # the prefix itself is stripped from the stored body
    end
  end

  test "typing a profile's chat proxy brackets in a different case does not match — falls back to the default" do
    profiles(:bob).update!(chat_bracket_before: "bob:")

    sign_in_via_browser(@owner)
    visit chat_url(channel_path)

    fill_in placeholder: "Message ##{@channel.name} (Enter to send, Shift+Enter for a new line)", with: "BOB: shouting today"

    # The live "Posting as" preview (composer_controller.js#matchProxy) should
    # NOT have switched — case-sensitive brackets can identify two different
    # profiles ("bob:" vs "BOB:"), so a case mismatch is simply no match.
    assert_selector ".profile-picker__trigger", text: profiles(:alice).name
    assert_no_selector ".profile-picker__trigger", text: profiles(:bob).name

    find("textarea").native.send_keys(:enter)

    within("#chat-messages") do
      assert_text "BOB: shouting today"
      assert_text profiles(:alice).name
      assert_no_text profiles(:bob).name
    end
  end

  test "switching the posting-as identity to a group changes whose name is attached to new messages" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path)

    assert_text "Posting as"
    assert_text profiles(:alice).name

    within(".composer-posting-as") do
      find(".profile-picker__trigger").click
      click_link groups(:friends).name
    end

    assert_selector ".profile-picker__trigger", text: groups(:friends).name

    send_message("Posting for the whole group")

    within("#chat-messages") do
      assert_text "Posting for the whole group"
      assert_text groups(:friends).name
      assert_no_text profiles(:alice).name
    end
  end

  test "typing a group's chat proxy brackets posts as that group instead of the default" do
    groups(:friends).update!(chat_bracket_before: "us:")

    sign_in_via_browser(@owner)
    visit chat_url(channel_path)

    send_message("us: heading out together")

    within("#chat-messages") do
      assert_text "heading out together"
      assert_text groups(:friends).name
      assert_no_text "us:" # the prefix itself is stripped from the stored body
    end
  end

  test "an unread dot lights up a channel and server that a message arrives in, and clears on read" do
    using_session(:owner) do
      sign_in_via_browser(@owner)
      # Sitting on the server page (not the channel), so the new message
      # shouldn't be marked read just from this.
      visit chat_url("/servers/#{@server.uuid}")
      within(".channel-pane") { assert_no_selector ".unread-dot" }
    end

    using_session(:member) do
      sign_in_via_browser(@member)
      visit chat_url(channel_path)
      send_message("Anybody around?")
    end

    using_session(:owner) do
      within(".channel-pane") { assert_selector ".unread-dot" }
      within(".server-rail") { assert_selector ".unread-dot--rail" }

      within(".channel-pane") { click_link "general" }
      assert_text "Anybody around?"

      # mark_read fires client-side once the channel page has mounted
      # (see channel_read_controller.js) rather than on the GET itself.
      within(".channel-pane") { assert_no_selector ".unread-dot" }
      within(".server-rail") { assert_no_selector ".unread-dot--rail" }
    end
  end

  test "unread channels and servers say so to screen readers, not just with a dot" do
    other_server = @owner.owned_chat_servers.create!(name: "Busy Server")
    other_server.memberships.create!(user: @owner, role: "owner", default_postable: profiles(:alice))
    other_server.channels.create!(name: "lobby").messages.create!(user: @member, postable: profiles(:carol), postable_name: "Carol", body: "hi")
    @other_channel.messages.create!(user: @member, postable: profiles(:carol), postable_name: "Carol", body: "hello")

    sign_in_via_browser(@owner)
    visit chat_url(channel_path)
    within(".channel-pane") { assert_selector ".unread-dot", count: 1, visible: :all }

    assert_equal "# off-topic (unread)", accessible_name(".channel-pane a", text: "off-topic")
    assert_equal "# general", accessible_name(".channel-pane a", text: "general")
    assert_equal "Busy Server (unread)", accessible_name(".server-rail a[title='Busy Server']")
    assert_equal "Live Server (unread)", accessible_name(".server-rail a[title='Live Server']")
  end

  test "a page whose live connection dropped catches up on what it missed once it reconnects" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path)
    assert_text "No messages yet. Say hello!"
    wait_for_live_connection
    fill_in placeholder: "Message ##{@channel.name} (Enter to send, Shift+Enter for a new line)", with: "Half a thought"

    # As when a laptop sleeps: the socket goes, and Action Cable reopens it
    # a few seconds later by itself
    ActionCable.server.remote_connections.where(current_user: @owner).disconnect
    assert_no_selector "turbo-cable-stream-source[connected]", visible: false

    # Broadcast while nobody was listening, so it can only appear by the page
    # catching up
    @channel.messages.create!(user: @member, postable: profiles(:carol), postable_name: "Carol", body: "Sent while you were away")

    assert_text "Sent while you were away", wait: 30
    assert_equal "Half a thought", find("textarea[data-composer-target='textarea']").value
    wait_for_live_connection
  end

  test "a page doesn't reload over unsaved changes in another form when it reconnects" do
    sign_in_via_browser(@owner)
    visit chat_url("/servers/#{@server.uuid}/channels/#{@channel.uuid}/edit")
    wait_for_live_connection
    fill_in "Name", with: "renamed"

    drop_connection_and_wait_for_it_to_come_back_without_reloading

    assert_equal "renamed", find_field("Name").value
  end

  test "a page doesn't reload over a profile picked but not yet saved when it reconnects" do
    sign_in_via_browser(@owner)
    visit chat_url("/servers/#{@server.uuid}/membership/edit")
    wait_for_live_connection
    find(".profile-picker__trigger").click
    find(".profile-picker__option", text: "Bob").click
    assert_equal profiles(:bob).id.to_s, find("input[name='default_postable_id']", visible: false).value

    drop_connection_and_wait_for_it_to_come_back_without_reloading

    assert_equal profiles(:bob).id.to_s, find("input[name='default_postable_id']", visible: false).value
  end

  test "a page doesn't reload over a message it couldn't keep for afterwards" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path)
    wait_for_live_connection
    # As with storage switched off or full, so the draft can't be kept as
    # it's typed
    page.execute_script("Storage.prototype.setItem = () => { throw new DOMException('full', 'QuotaExceededError') }")
    fill_in placeholder: "Message ##{@channel.name} (Enter to send, Shift+Enter for a new line)", with: "Nowhere to put this"

    drop_connection_and_wait_for_it_to_come_back_without_reloading

    assert_equal "Nowhere to put this", find("textarea[data-composer-target='textarea']").value
  end

  test "a page whose session ended while it was away goes to sign in, and keeps the message for afterwards" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path)
    wait_for_live_connection
    fill_in placeholder: "Message ##{@channel.name} (Enter to send, Shift+Enter for a new line)", with: "Still here"

    # Signed out elsewhere: the server now refuses to reconnect this page, and
    # Action Cable gives up
    @owner.sessions.destroy_all
    ActionCable.server.remote_connections.where(current_user: @owner).disconnect

    assert_field "Email address or account name", wait: 40
    fill_in "Email address or account name", with: @owner.email_address
    fill_in "Password", with: "Plur4l!Pr0files#2026"
    click_button "Sign in"

    assert_text "No messages yet. Say hello!"
    assert_equal "Still here", find("textarea[data-composer-target='textarea']").value
  end

  private

  def drop_connection_and_wait_for_it_to_come_back_without_reloading
    page.execute_script("document.body.dataset.notReloaded = 'true'")
    ActionCable.server.remote_connections.where(current_user: @owner).disconnect
    assert_no_selector "turbo-cable-stream-source[connected]", visible: false
    assert_selector "turbo-cable-stream-source[connected]", visible: false, wait: 30
    # A reload would start straight after reconnecting; give it time to land
    sleep 2
    assert_selector "body[data-not-reloaded]"
  end

  # What a screen reader announces for the element, as Chrome computes it
  def accessible_name(selector, **options)
    find(selector, **options).native.accessible_name
  end

  # Every turbo_stream_from on the page has subscribed
  def wait_for_live_connection
    assert_no_selector "turbo-cable-stream-source:not([connected])", visible: false
    assert_selector "turbo-cable-stream-source[connected]", visible: false
  end
end
