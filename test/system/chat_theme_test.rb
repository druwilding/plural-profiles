require "application_system_test_case"

# Verifies the chat palette actually reaches the pixels: that each region reads
# its own chat_* variable, and — the part that can't be checked by reading the
# stylesheet — that the specificity works out so a single-purpose rule isn't
# quietly outranked by a broader one.
class ChatThemeTest < ApplicationSystemTestCase
  setup do
    @port = Capybara.current_session.server.port
    Capybara.app_host = "http://lvh.me:#{@port}"

    @user = users(:one)
    @theme = @user.themes.create!(name: "Chat palette test", colors: base_colors)
    @user.update!(active_theme: @theme, override_themes: true)

    @server = @user.owned_chat_servers.create!(name: "Themed Server")
    @server.memberships.create!(user: @user, role: "owner", default_postable: profiles(:alice))
    @channel = @server.channels.create!(name: "general")
  end

  teardown do
    Capybara.app_host = nil
  end

  # Deliberately garish and all-distinct, so any region reading the wrong
  # variable shows up as a mismatch rather than an accidental match.
  def base_colors
    {
      "page_bg" => "#010203", "pane_bg" => "#040506", "pane_border" => "#070809",
      "pane_text" => "#0a0b0c", "pane_title_text" => "#0d0e0f", "pane_link" => "#101112",
      "header_bg" => "#131415", "header_text" => "#161718", "header_title_text" => "#191a1b",
      "header_link" => "#1c1d1e", "spoiler" => "#1f2021",
      "input_bg" => "#222324", "input_border" => "#252627", "input_text" => "#28292a"
    }
  end

  def chat_url(path)
    "http://chat.lvh.me:#{@port}#{path}"
  end

  def channel_path
    "/servers/#{@server.uuid}/channels/#{@channel.uuid}"
  end

  # Selenium serialises computed colours as "rgba(r, g, b, 1)"; compare in that
  # space so we don't depend on how the browser renders a hex back to a string.
  def rgb(hex)
    r, g, b = hex.delete("#").scan(/../).map { |pair| pair.to_i(16) }
    "rgba(#{r}, #{g}, #{b}, 1)"
  end

  def style_of(selector, property)
    find(selector, match: :first, visible: :all).native.style(property)
  end

  test "an untouched theme renders every chat region with its inherited profile colour" do
    sign_in_via_browser
    visit chat_url(channel_path)
    assert_text "No messages yet. Say hello!"

    # The no-migration promise, checked against real computed styles: with no
    # chat_* key set, each region still shows exactly what it showed when these
    # rules read the profile variables directly.
    assert_equal rgb("#070809"), style_of(".server-rail", "background-color"), "server rail should inherit pane_border"
    assert_equal rgb("#040506"), style_of(".channel-pane", "background-color"), "channel list should inherit pane_bg"
    assert_equal rgb("#040506"), style_of(".chat-main", "background-color"), "message pane should inherit pane_bg"
    assert_equal rgb("#131415"), style_of(".site-header", "background-color"), "chat header should inherit header_bg"
    assert_equal rgb("#191a1b"), style_of(".site-header .logo", "color"), "logo should inherit header_title_text"
    assert_equal rgb("#0d0e0f"), style_of(".channel-pane__server-name", "color"), "server name should inherit pane_title_text"
    assert_equal rgb("#101112"), style_of(".channel-pane .sidebar-tree__leaf", "color"), "channel names should inherit pane_link"
    assert_equal rgb("#222324"), style_of(".composer-input-row textarea", "background-color"), "composer input should inherit input_bg"
  end

  test "the server rail and the divider bars can be coloured apart" do
    # The headline complaint: both were --pane-border, so they could never
    # differ no matter what the designer did.
    @theme.update!(colors: base_colors.merge("chat_rail_bg" => "#ff0000", "chat_divider" => "#00ff00"))

    sign_in_via_browser
    visit chat_url(channel_path)
    assert_text "No messages yet. Say hello!"

    assert_equal rgb("#ff0000"), style_of(".server-rail", "background-color")
    assert_equal rgb("#00ff00"), style_of(".channel-pane", "border-right-color")
    assert_equal rgb("#00ff00"), style_of(".chat-channel-header", "border-bottom-color")
    assert_equal rgb("#00ff00"), style_of(".composer", "border-top-color")
  end

  test "the channel list and the message pane can be coloured apart" do
    # The second complaint: both were --pane-bg.
    @theme.update!(colors: base_colors.merge("chat_sidebar_bg" => "#ff0000", "chat_pane_bg" => "#0000ff"))

    sign_in_via_browser
    visit chat_url(channel_path)
    assert_text "No messages yet. Say hello!"

    assert_equal rgb("#ff0000"), style_of(".channel-pane", "background-color")
    assert_equal rgb("#0000ff"), style_of(".chat-main", "background-color")
  end

  test "chat header, channel list and message titles no longer share one colour" do
    # The third complaint: pane_title_text spanned all three at once.
    @theme.update!(colors: base_colors.merge(
      "chat_topbar_title_text" => "#ff0000",
      "chat_sidebar_title_text" => "#00ff00",
      "chat_pane_title_text" => "#0000ff"
    ))

    # Seeded rather than typed: posting through the composer triggers a Turbo
    # broadcast that re-renders the message list, and the replaced node goes
    # stale between finding it and reading its computed style.
    @channel.messages.create!(user: @user, postable: profiles(:alice), body: "hello")

    sign_in_via_browser
    visit chat_url(channel_path)
    assert_text "hello"

    assert_equal rgb("#ff0000"), style_of(".chat-channel-header h1", "color")
    assert_equal rgb("#00ff00"), style_of(".channel-pane__server-name", "color")
    assert_equal rgb("#0000ff"), style_of(".chat-message__name", "color")
  end

  test "the chat link colour does not flatten the channel list or the rail" do
    # Regression guard for specificity: a plain `.chat-body a` rule would
    # outrank every single-class rule colouring a link in chat and paint the
    # channel names, the "+ Add channel" link and the rail all one colour.
    @theme.update!(colors: base_colors.merge(
      "chat_pane_link" => "#ff0000",
      "chat_sidebar_link" => "#00ff00"
    ))

    sign_in_via_browser
    visit chat_url(channel_path)
    assert_text "No messages yet. Say hello!"

    assert_equal rgb("#00ff00"), style_of(".channel-pane .sidebar-tree__leaf", "color")
    assert_equal rgb("#00ff00"), style_of(".channel-pane__add-channel", "color")
    assert_not_equal rgb("#ff0000"), style_of(".channel-pane__server-name", "color"),
      "the server name should keep its title colour, not the pane link colour"
  end

  # An unread channel in *this* server puts a dot in the channel list; an
  # unread channel in another server puts one on the rail. Both at once, so a
  # single page shows the two surfaces together.
  def seed_unread_dots
    other = @user.owned_chat_servers.create!(name: "Unread Server")
    other.memberships.create!(user: @user, role: "owner", default_postable: profiles(:alice))
    other.channels.create!(name: "elsewhere").messages.create!(
      user: users(:two), postable: profiles(:carol), body: "over here"
    )
    @server.channels.create!(name: "noisy").messages.create!(
      user: users(:two), postable: profiles(:carol), body: "hello there"
    )
  end

  test "the rail and channel-list unread dots can be coloured apart" do
    # They sit on different surfaces, so one key would force a compromise on
    # whichever surface lost.
    @theme.update!(colors: base_colors.merge(
      "primary_button_text" => "#010101",
      "chat_rail_unread_dot" => "#ff0000",
      "chat_sidebar_unread_dot" => "#0000ff"
    ))
    seed_unread_dots

    sign_in_via_browser
    visit chat_url(channel_path)
    assert_selector ".unread-dot--rail"
    assert_selector ".channel-pane .unread-dot"

    assert_equal rgb("#ff0000"), style_of(".unread-dot--rail", "background-color")
    assert_equal rgb("#0000ff"), style_of(".channel-pane .unread-dot", "background-color")
    assert_equal rgb("#070809"), style_of(".unread-dot--rail", "border-top-color"),
      "the rail dot's ring should match the rail background it sits on"
  end

  test "both unread dots follow the primary button text until overridden" do
    @theme.update!(colors: base_colors.merge("primary_button_text" => "#ff0000"))
    seed_unread_dots

    sign_in_via_browser
    visit chat_url(channel_path)
    assert_selector ".unread-dot--rail"
    assert_selector ".channel-pane .unread-dot"

    assert_equal rgb("#ff0000"), style_of(".unread-dot--rail", "background-color")
    assert_equal rgb("#ff0000"), style_of(".channel-pane .unread-dot", "background-color")
  end

  test "a placeholder avatar takes the colour of the region it sits in" do
    # The chat-wide placeholder rule outranks the per-region colours, so
    # pinning it to the pane colour drew rail placeholders in message-pane text.
    @theme.update!(colors: base_colors.merge(
      "chat_rail_text" => "#ff0000", "chat_pane_text" => "#00ff00"
    ))

    sign_in_via_browser
    visit chat_url(channel_path)
    assert_text "No messages yet. Say hello!"

    assert_equal rgb("#ff0000"), style_of(".server-rail .avatar--placeholder", "color"),
      "a rail placeholder should use the rail text colour"
  end

  test "chat pages fall back to the profile page background behind their cards" do
    # Chat has no page colour of its own — the panes fill the window, and the
    # only place body shows through is behind the cards on the plain chat
    # pages, which keep --page-bg like every other page in the app.
    sign_in_via_browser
    visit chat_url("/servers")

    assert_equal rgb("#010203"), style_of("body", "background-color")
  end

  test "chat colours do not leak onto profile pages" do
    @theme.update!(colors: base_colors.merge("chat_pane_bg" => "#ff0000", "chat_header_bg" => "#00ff00"))

    sign_in_via_browser
    visit root_path

    assert_equal rgb("#010203"), style_of("body", "background-color"), "profile pages keep page_bg"
    assert_equal rgb("#131415"), style_of(".site-header", "background-color"), "profile pages keep header_bg"
    assert_equal rgb("#040506"), style_of(".card", "background-color"), "profile cards keep pane_bg"
  end

  test "profile colours still drive chat for keys the designer left alone" do
    # Half-designed theme: chat pane set, everything else inherited. Editing a
    # profile colour afterwards should still move the inherited chat regions.
    @theme.update!(colors: base_colors.merge("chat_pane_bg" => "#0000ff", "pane_border" => "#ff0000"))

    sign_in_via_browser
    visit chat_url(channel_path)
    assert_text "No messages yet. Say hello!"

    assert_equal rgb("#0000ff"), style_of(".chat-main", "background-color")
    assert_equal rgb("#ff0000"), style_of(".server-rail", "background-color"),
      "the rail should still track pane_border while chat_rail_bg is unset"
  end
end
