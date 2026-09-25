require "application_system_test_case"

# Emote autocomplete and the emote picker in the chat composer, where Enter
# normally sends the message — see emote_input_test.rb for the form fields.
class EmoteInputComposerTest < ApplicationSystemTestCase
  setup do
    @port = Capybara.current_session.server.port
    Capybara.app_host = "http://lvh.me:#{@port}"

    @user = users(:one)
    @server = @user.owned_chat_servers.create!(name: "Heart Server")
    @server.memberships.create!(user: @user, role: "owner", default_postable: profiles(:alice))
    @channel = @server.channels.create!(name: "general")

    sign_in_via_browser
    visit "http://chat.lvh.me:#{@port}/servers/#{@server.uuid}/channels/#{@channel.uuid}"
    assert_text "No messages yet. Say hello!"
  end

  teardown do
    Capybara.app_host = nil
  end

  def composer
    find(".composer-input-row textarea")
  end

  test "Enter inserts the highlighted heart instead of sending, then sends once the menu is closed" do
    composer.send_keys(";ab")
    assert_selector ".composer .emote-input__option--active", text: "abyss heart"

    composer.send_keys(:enter)
    assert_equal ":abyss-heart: ", composer.value
    assert_text "No messages yet. Say hello!"
    assert_equal 0, @channel.messages.count

    composer.send_keys("hello", :enter)
    assert_selector ".chat-message__body img.emote-inline[alt='abyss heart']"
    assert_equal ":abyss-heart: hello", @channel.messages.last.body.strip
  end

  test "Shift+Enter still adds a new line while the menu is open" do
    composer.send_keys(";ab")
    assert_selector ".composer .emote-input__menu", visible: true

    composer.send_keys([ :shift, :enter ])
    assert_equal ";ab\n", composer.value
    assert_no_selector ".composer .emote-input__menu", visible: true
    assert_equal 0, @channel.messages.count
  end

  test "the menu opens above the composer" do
    composer.send_keys(":ab")
    assert_selector ".composer .emote-input__option--active", text: "abyss heart"

    menu_top, menu_bottom, field_top, field_bottom = page.evaluate_script(<<~JS)
      (() => {
        const field = document.querySelector(".composer-input-row textarea").getBoundingClientRect()
        const menu = document.querySelector(".composer .emote-input__menu").getBoundingClientRect()
        return [menu.top, menu.bottom, field.top, field.bottom]
      })()
    JS
    assert menu_top < field_top, "expected the menu to start above the composer"
    assert menu_bottom < field_bottom, "expected the menu to end above the composer's bottom edge"
    assert menu_top >= 0, "expected the menu to stay on screen"
  end

  test "the emote button opens the picker from the composer" do
    find(".composer-input-row .emote-input__button").click
    within("dialog.emote-dialog[open]") { click_button "red heart" }

    assert_field with: ":red-heart: "
    assert_equal 0, @channel.messages.count
  end
end
