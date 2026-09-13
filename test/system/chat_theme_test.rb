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

  test "both unread dots follow the pane text until overridden" do
    # Pane text rather than the primary button's text colour they used to
    # borrow: button text is often near-black, which left the dots invisible.
    @theme.update!(colors: base_colors.merge("pane_text" => "#ff0000"))
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

  test "chat colours do not reach the ordinary pages inside the chat layout" do
    # The server list, settings and invite pages are plain profile-page
    # furniture that happens to render inside the chat layout. A colour chosen
    # to look right on the message pane looks wrong on them — a message-author
    # colour landing on an invite card's heading, say — so they keep the
    # profile palette and only the chat view proper is repainted.
    @theme.update!(colors: base_colors.merge(
      "chat_pane_bg" => "#ff0000", "chat_pane_title_text" => "#ff00ff",
      "chat_pane_text" => "#ff8800", "chat_divider" => "#00ff00"
    ))

    sign_in_via_browser
    visit chat_url("/servers/#{@server.uuid}/invite")
    assert_text "Invite people"

    assert_equal rgb("#040506"), style_of(".card", "background-color"), "cards keep pane_bg"
    assert_equal rgb("#070809"), style_of(".card", "border-top-color"), "cards keep pane_border"
    assert_equal rgb("#131415"), style_of(".card > .card__header", "background-color"), "card banners keep header_bg"
    assert_equal rgb("#191a1b"), style_of(".card > .card__header h2", "color"), "banner titles keep header_title_text"
    assert_equal rgb("#0d0e0f"), style_of(".invite-card__title", "color"), "headings keep pane_title_text"
    assert_equal rgb("#0a0b0c"), style_of(".invite-generator", "color"), "body text keeps pane_text"
  end

  test "the chat view itself still takes the chat colours" do
    @theme.update!(colors: base_colors.merge(
      "chat_pane_bg" => "#ff0000", "chat_pane_title_text" => "#ff00ff", "chat_pane_text" => "#ff8800"
    ))
    @channel.messages.create!(user: @user, postable: profiles(:alice), body: "hello")

    sign_in_via_browser
    visit chat_url(channel_path)
    assert_text "hello"

    assert_equal rgb("#ff0000"), style_of(".chat-main", "background-color")
    assert_equal rgb("#ff00ff"), style_of(".chat-message__name", "color")
    assert_equal rgb("#ff8800"), style_of(".chat-message__body", "color")
  end

  test "the server list keeps the profile text colour" do
    # /servers is an ordinary page inside the chat layout; the original
    # conversion of the chat stylesheet had pointed its links at the
    # message-pane colour.
    @theme.update!(colors: base_colors.merge("chat_pane_text" => "#ff0000"))

    sign_in_via_browser
    visit chat_url("/servers")
    assert_text "Your servers"

    assert_equal rgb("#0a0b0c"), style_of(".server-list__link", "color")
  end

  test "the invite card's description keeps the profile text colour" do
    @server.update!(description: "A quiet place")
    @theme.update!(colors: base_colors.merge("chat_pane_text" => "#ff0000"))

    sign_in_via_browser
    visit chat_url("/servers/#{@server.uuid}/invite")
    assert_text "A quiet place"

    # An 80% mix, so the browser reports color(srgb r g b / 0.8): pane_text
    # (#0a0b0c) gives ~0.039 per channel, where the chat red would give 1 0 0.
    color = style_of(".invite-card__description", "color")
    assert_match(/srgb 0\.039/, color, "expected the profile text colour, got #{color}")
  end

  test "the composer's identity picker takes chat colours but the plain-form picker keeps profile colours" do
    # Same .profile-picker markup in both places; only the composer's copy is
    # chat chrome. The server create form's picker is an ordinary form field.
    @theme.update!(colors: base_colors.merge("chat_composer_highlight" => "#ff0000"))

    sign_in_via_browser
    visit chat_url(channel_path)
    assert_text "No messages yet. Say hello!"
    assert_equal rgb("#ff0000"), style_of(".composer .profile-picker", "background-color")

    visit chat_url("/servers/new")
    assert_selector ".profile-picker", visible: :all
    assert_not_equal rgb("#ff0000"), style_of(".profile-picker", "background-color"),
      "the plain-form picker must not take the composer highlight"
  end

  test "the composer's posting-as options take the chat footer text colour" do
    # The options are action-dropdown items too, so the generic channel
    # dropdown rule used to paint them in the message-pane colour and the Chat
    # footer text colour never reached them.
    @theme.update!(colors: base_colors.merge("chat_pane_text" => "#0000ff", "chat_composer_text" => "#ff0000"))

    sign_in_via_browser
    visit chat_url(channel_path)
    assert_text "No messages yet. Say hello!"

    option = find(".composer .profile-picker__option.action-dropdown__item", match: :first, visible: :all)
    assert_equal rgb("#ff0000"), option.native.style("color")
  end

  # Emulated forced-colors applies the @media (forced-colors: active) rules.
  # Every value below is read with getComputedStyle, and each system colour is
  # resolved the same way on a throwaway element, so the comparison doesn't
  # depend on what the emulated palette happens to be.
  def with_forced_colors
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
      features: [ { name: "forced-colors", value: "active" } ])
    yield
  ensure
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "chat-themed controls fall back to system colours in forced-colors mode" do
    # The chat-scoped rules used to outrank the base forced-colors ones. For the
    # textarea and spoilers that's under forced-color-adjust: none, so a
    # high-contrast user would have seen the chat theme's colours as written.
    @theme.update!(colors: base_colors.merge(
      "chat_input_bg" => "#ff0000", "chat_input_text" => "#ff0000",
      "chat_spoiler" => "#00ff00", "chat_sidebar_text" => "#0000ff"
    ))
    @channel.messages.create!(user: @user, postable: profiles(:alice), body: "a ||secret|| here")

    sign_in_via_browser
    visit chat_url(channel_path)
    assert_text "here"

    with_forced_colors do
      probe = page.evaluate_script(<<~JS)
        (() => {
          const sys = (keyword, prop) => {
            const el = document.createElement("div")
            el.style.forcedColorAdjust = "none"
            el.style[prop] = keyword
            document.body.appendChild(el)
            const value = getComputedStyle(el)[prop]
            el.remove()
            return value
          }
          const cs = selector => getComputedStyle(document.querySelector(selector))
          return {
            canvas: sys("Canvas", "backgroundColor"),
            canvasText: sys("CanvasText", "color"),
            highlight: sys("Highlight", "backgroundColor"),
            textareaBg: cs(".composer-input-row textarea").backgroundColor,
            textareaText: cs(".composer-input-row textarea").color,
            spoilerEdge: cs(".chat-message__body .spoiler").borderTopColor,
            activeBg: cs(".channel-pane .sidebar-tree__leaf--active").backgroundColor
          }
        })()
      JS

      assert_equal probe["canvas"], probe["textareaBg"], "composer textarea background should be Canvas"
      assert_equal probe["canvasText"], probe["textareaText"], "composer textarea text should be CanvasText"
      assert_equal probe["canvasText"], probe["spoilerEdge"], "a hidden spoiler's edge should be CanvasText"
      assert_equal probe["highlight"], probe["activeBg"], "the active channel should be marked with Highlight"
    end
  end

  test "the header bar stays chat-coloured on the ordinary chat pages too" do
    # It's chat chrome, visible on every page in the layout, so unlike the
    # cards below it, it does follow the chat palette throughout.
    @theme.update!(colors: base_colors.merge("chat_header_bg" => "#ff0000"))

    sign_in_via_browser
    visit chat_url("/servers")
    assert_text "Your servers"

    assert_equal rgb("#ff0000"), style_of(".site-header", "background-color")
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
