require "application_system_test_case"

# An unsent message stays with its channel (chat_drafts.js), so looking
# something up in another channel or server doesn't lose it.
class ChatDraftsTest < ApplicationSystemTestCase
  setup do
    @port = Capybara.current_session.server.port
    Capybara.app_host = "http://lvh.me:#{@port}"

    @owner = users(:one)
    @member = users(:two)

    @server = @owner.owned_chat_servers.create!(name: "Draft Server")
    @server.memberships.create!(user: @owner, role: "owner", default_postable: profiles(:alice))
    @server.memberships.create!(user: @member, role: "member", default_postable: profiles(:carol))
    @general = @server.channels.create!(name: "general")
    @off_topic = @server.channels.create!(name: "off-topic")

    @other_server = @owner.owned_chat_servers.create!(name: "Other Server")
    @other_server.memberships.create!(user: @owner, role: "owner", default_postable: profiles(:alice))
    @lobby = @other_server.channels.create!(name: "lobby")
  end

  teardown do
    Capybara.app_host = nil
  end

  test "a draft is still there after going to another channel and back" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    type_message "Half a thought", @general

    within(".channel-pane") { click_link "off-topic" }
    assert_draft "off-topic", ""

    within(".channel-pane") { click_link "general" }
    assert_draft "general", "Half a thought"
  end

  test "a draft is still there after going to another server and back" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    type_message "Back in a moment", @general

    find(".server-rail a[title='Other Server']").click
    within(".channel-pane") { click_link "lobby" }
    assert_draft "lobby", ""

    find(".server-rail a[title='Draft Server']").click
    within(".channel-pane") { click_link "general" }
    assert_draft "general", "Back in a moment"
  end

  test "a draft is still there after a reload" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    type_message "Survives a reload", @general

    visit chat_url(channel_path(@general))
    assert_draft "general", "Survives a reload"
  end

  test "sending a message clears its draft" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    type_message "On its way", @general
    composer.native.send_keys(:enter)
    within("#chat-messages") { assert_text "On its way" }
    # The message can arrive live before the page reloads after sending
    assert_field placeholder: "Message #general (Enter to send, Shift+Enter for a new line)", with: ""

    within(".channel-pane") { click_link "off-topic" }
    assert_selector "h1", text: "# off-topic"
    within(".channel-pane") { click_link "general" }
    assert_draft "general", ""
  end

  test "going back to a channel after sending doesn't clear a newer draft" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    type_message "First", @general
    composer.native.send_keys(:enter)
    assert_draft "general", ""
    type_message "Second thoughts", @general

    within(".channel-pane") { click_link "off-topic" }
    assert_draft "off-topic", ""
    # Restored from Turbo's cache of the page straight after sending
    page.go_back
    assert_draft "general", "Second thoughts"

    visit chat_url(channel_path(@general))
    assert_draft "general", "Second thoughts"
  end

  # The same as a send that's too fast: redirected without saving. The browser
  # can't tell either from a send that worked.
  test "a send the server turns away keeps its draft" do
    sign_in_via_browser(@member)
    visit chat_url(channel_path(@general))
    type_message "Please don't lose this", @general
    @server.memberships.find_by!(user: @member).destroy!

    composer.native.send_keys(:enter)
    assert_text "You need a valid invite link to join this server."

    @server.memberships.create!(user: @member, role: "member", default_postable: profiles(:carol))
    visit chat_url(channel_path(@general))
    assert_draft "general", "Please don't lose this"
  end

  test "emptying the message box clears its draft" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    type_message "Never mind", @general
    composer.set("")

    visit chat_url(channel_path(@general))
    assert_draft "general", ""
  end

  test "a draft only comes back for the account that typed it" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    type_message "Just for me", @general

    # Someone else signs in to the same browser, without signing the first
    # account out
    @owner.sessions.destroy_all
    sign_in_via_browser(@member)
    visit chat_url(channel_path(@general))
    assert_draft "general", ""

    @member.sessions.destroy_all
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    assert_draft "general", "Just for me"
  end

  test "signing out of the chat clears the account's drafts" do
    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    type_message "Not for the next person", @general

    click_button "Sign out"
    assert_current_path new_session_path

    sign_in_via_browser(@owner)
    visit chat_url(channel_path(@general))
    assert_draft "general", ""
  end

  private

  def chat_url(path)
    "http://chat.lvh.me:#{@port}#{path}"
  end

  def channel_path(channel)
    "/servers/#{channel.server.uuid}/channels/#{channel.uuid}"
  end

  def composer
    find("textarea[data-composer-target='textarea']")
  end

  # Once the channel's page has really loaded: following a link to a page
  # visited before shows Turbo's cached copy first, which still holds
  # whatever was typed when it was cached
  def assert_draft(channel_name, text)
    assert_selector "h1", text: "# #{channel_name}"
    assert_no_selector "html[data-turbo-preview]", visible: :all
    assert_field placeholder: "Message ##{channel_name} (Enter to send, Shift+Enter for a new line)", with: text
  end

  def type_message(text, channel)
    fill_in placeholder: "Message ##{channel.name} (Enter to send, Shift+Enter for a new line)", with: text
  end
end
