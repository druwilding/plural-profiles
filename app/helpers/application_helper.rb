module ApplicationHelper
  # Links from chat pages/broadcasts to public profile/group pages should never
  # carry the chat. subdomain — those pages aren't chat-namespaced routes, and
  # a chat. URL for them just reads as a broken/wrong link when shared.
  def main_site_host
    request.host.sub(/\Achat\./, "")
  end

  def chat_site_host
    "chat.#{main_site_host}"
  end

  def chat_date_divider_label(date)
    case date
    when Date.current then "Today"
    when Date.current - 1 then "Yesterday"
    else date.strftime("%A, %-d %B %Y")
    end
  end

  DESCRIPTION_EXTRA_TAGS = %w[details summary span b i u s table thead tbody tfoot tr th td].to_set.freeze
  DESCRIPTION_EXTRA_ATTRIBUTES = %w[open class role tabindex aria-label aria-expanded colspan rowspan data-spoiler-hint style width height].to_set.freeze

  ALLOWED_CSS_PROPERTIES = %w[
    float clear
    width height max-width max-height min-width min-height
    padding padding-top padding-right padding-bottom padding-left
    margin margin-top margin-right margin-bottom margin-left
    text-align vertical-align
    border-radius
  ].to_set.freeze

  INLINE_EXTRA_TAGS = %w[b strong i em u s del span sup sub].to_set.freeze
  INLINE_EXTRA_ATTRS = %w[class role tabindex aria-expanded aria-label
                          data-spoiler-hint src alt width height loading title].to_set.freeze

  SPOILER_PLAIN_PATTERN = /(?:\[[^\]]+\]\s*)?\|\|(.+?)\|\|(?:\s*\[[^\]]+\])?/m

  # Matches ||spoiler|| with an optional [hint] on either side:
  #   ||secret||[hint text]   or   [hint text]||secret||
  SPOILER_HINT_PATTERN = /(?:\[(?<pre_hint>[^\]]+)\]\s*)?\|\|(?<content>.+?)\|\|(?:\s*\[(?<post_hint>[^\]]+)\])?/m
  CODE_BLOCK_PATTERN = /<code(?:\s[^>]*)?>.*?<\/code>/m

  # Newlines adjacent to these block-level tags get stripped before newline→<br>
  # conversion, to prevent spurious <br> inside structured HTML like tables.
  # Limited to table structural tags — other block elements (div, details, etc.)
  # can appear in flow text where blank lines ARE meaningful line breaks.
  BLOCK_TAG_NAMES = "table|thead|tbody|tfoot|tr|th|td"
  BLOCK_TAG_TRAILING_NEWLINE_RE = Regexp.new(
    "(</?(?:#{BLOCK_TAG_NAMES})(?:\\s[^>]*)?>)\\s*\\n+\\s*",
    Regexp::IGNORECASE
  ).freeze
  BLOCK_TAG_LEADING_NEWLINE_RE = Regexp.new(
    "\\s*\\n+\\s*(?=</?(?:#{BLOCK_TAG_NAMES})\\b)",
    Regexp::IGNORECASE
  ).freeze

  # What replace_emote_codes skips over when looking for emote codes: <code>
  # blocks, HTML tags and entities. Captured so split keeps them.
  EMOTE_SKIP_PATTERN = /(#{CODE_BLOCK_PATTERN}|<[^>]*>|&(?:[a-z][a-z0-9]*|#\d+|#x\h+);)/mi

  # Tags that start a new line, for finding emotes on a line of their own.
  # Includes button for the block-level "(click to close)" added to <details>.
  LINE_BREAK_TAG_PATTERN = %r{\A</?(?:br|hr|p|div|pre|address|blockquote|ul|ol|li|dl|dt|dd|h[1-6]|details|summary|button|#{BLOCK_TAG_NAMES})\b}i

  # Emotes on a line of their own are shown large, unless there are more
  # than this many of them (as Discord does).
  LARGE_EMOTE_LIMIT = 30

  def formatted_description(text)
    text = text.gsub(/\r\n?/, "\n")
    safe_list_class = self.class.safe_list_sanitizer.class
    tags = safe_list_class.allowed_tags + DESCRIPTION_EXTRA_TAGS
    attrs = safe_list_class.allowed_attributes + DESCRIPTION_EXTRA_ATTRIBUTES
    text = convert_spoilers_outside_code(text)
    text = strip_block_tag_newlines(text)
    html = sanitize(text, tags: tags, attributes: attrs)
    html = newlines_to_br(html)
    html = sanitize_inline_styles(html)
    html = html.gsub("</details>", '<button type="button" class="details-close" aria-label="Close details">(click to close)</button></details>')
    html = replace_emote_codes(html, large_emotes: true)
    html.html_safe
  end

  # Single-line fields leave large_emotes off, since every emote in them would
  # otherwise be on a line of its own. Chat messages turn it on.
  def formatted_inline(text, large_emotes: false)
    return "".html_safe if text.blank?
    safe_list_class = self.class.safe_list_sanitizer.class
    tags = safe_list_class.allowed_tags + INLINE_EXTRA_TAGS
    attrs = safe_list_class.allowed_attributes + INLINE_EXTRA_ATTRS
    html = convert_spoilers_outside_code(text)
    html = sanitize(html, tags: tags, attributes: attrs)
    html = replace_emote_codes(html, large_emotes: large_emotes)
    html.html_safe
  end

  def plain_field(text)
    return "" if text.blank?
    text = text.gsub(SPOILER_PLAIN_PATTERN, "▓▓▓▓")
    text = EmoteRegistry.current.replace_codes(text) { |emote| "[#{emote.label}]" }
    strip_tags(text)
  end

  # Every pickable emote as JSON for emote_input_controller.js, in display
  # order, rendered once per page (at the end of the body) so the registry
  # stays the single source of truth.
  def emote_list_json_tag
    registry = EmoteRegistry.current
    emotes = registry.pickable.map do |emote|
      { name: emote.name, label: emote.label, src: emote.src, code: ":#{emote.code}:", group: registry.group(emote.group_id)&.name }
    end
    tag.script(emotes.to_json.html_safe, type: "application/json", id: "emote-list")
  end

  # A text field (or textarea, with as: :text_area) that accepts emote codes,
  # wrapped so emote_input_controller.js can add the emote picker button and
  # the :ab autocomplete menu. The field keeps its normal id, so form.label
  # still points at it. `data` is merged onto the field, not the wrapper.
  # menu_placement: "above" opens the autocomplete menu upwards, for fields
  # pinned to the bottom of the screen (the chat composer).
  def emote_field(form, method, as: :text_field, menu_placement: "below", **options)
    field_data = (options.delete(:data) || {}).merge("emote-input-target": "field")
    modifier = as == :text_area ? "emote-input--area" : "emote-input--line"

    tag.div(class: [ "emote-input", modifier ], data: { controller: "emote-input", "emote-input-placement-value": menu_placement }) do
      safe_join([
        form.public_send(as, method, **options, data: field_data),
        # Hidden until the controller connects, so there's no dead button without JS.
        tag.button(emote_button_icon, type: "button", class: "emote-input__button", hidden: true,
          title: "Insert an emote", "aria-label": "Insert an emote", "aria-haspopup": "dialog",
          data: { action: "emote-input#openPicker", "emote-input-target": "button" })
      ])
    end
  end

  def relative_time(time)
    return "unknown" unless time
    if time.future?
      "#{distance_of_time_in_words(Time.current, time)} from now"
    else
      "#{time_ago_in_words(time)} ago"
    end
  end

  def avatar_shape_class(record, prefix: "avatar", shape: record.avatar_shape)
    case shape
    when "circle" then "#{prefix}--circle"
    when "square" then "#{prefix}--square"
    else ""
    end
  end

  # The avatar chat should show for a postable. Gated on
  # mini_profile_avatar_inherited rather than attachment presence: shape and
  # alt text can be overridden independently of the image itself (see
  # chat_avatar_shape_for), so "inherited" is the actual source of truth —
  # attachment presence is only consulted as a fallback within the
  # not-inherited branch, for someone who's switched to "Set for chat" but
  # hasn't (yet, or ever) uploaded a replacement image.
  def chat_avatar_for(postable)
    return postable.avatar if postable.mini_profile_avatar_inherited?
    postable.mini_profile_avatar.attached? ? postable.mini_profile_avatar : postable.avatar
  end

  def chat_avatar_alt_text_for(postable)
    if postable.mini_profile_avatar_inherited?
      postable.avatar_alt_text.presence || ""
    else
      postable.mini_profile_avatar_alt_text.presence || ""
    end
  end

  # The shape to render chat_avatar_for(postable) with. Independent of
  # whether a replacement image was actually uploaded — someone can keep the
  # main avatar's image but still pick a different shape for chat, so this
  # follows mini_profile_avatar_inherited, not attachment presence. Message
  # rows ignore this entirely and always force circle for visual consistency
  # in the channel — only the popover (which shows "the chosen shape") should
  # call this.
  def chat_avatar_shape_for(postable)
    postable.mini_profile_avatar_inherited? ? postable.avatar_shape : postable.mini_profile_avatar_shape
  end

  # The default id for a postable's mini-profile turbo-frame. Only actually
  # unique per postable, not per message — when the same postable has
  # multiple messages in a channel, each one's own placeholder frame needs a
  # further per-message discriminator (see _message.html.haml) so the page
  # never has two elements sharing an id, and passes it to the popover route
  # as a frame_id param so the response's turbo-frame echoes the same id
  # back (Chat::MiniProfilesController#show falls back to this method's
  # output when that param is absent, e.g. someone hitting the route
  # directly).
  def mini_profile_frame_id(postable)
    "mini_profile_#{postable.class.name}_#{postable.uuid}"
  end

  private

  # An outlined heart that follows the text colour, so it suits every theme
  # and forced-colors mode (a coloured heart image would clash with some).
  def emote_button_icon
    tag.svg(
      tag.path(d: "M12 20.5s-7.5-4.6-9.4-9.3C1.2 7.6 3.4 4 6.9 4c2.1 0 3.8 1.2 5.1 3 1.3-1.8 3-3 5.1-3 3.5 0 5.7 3.6 4.3 7.2-1.9 4.7-9.4 9.3-9.4 9.3z"),
      class: "emote-input__icon", viewBox: "0 0 24 24", width: 18, height: 18, fill: "none",
      stroke: "currentColor", "stroke-width": 2, "stroke-linejoin": "round", "aria-hidden": "true", focusable: "false"
    )
  end

  def newlines_to_br(html)
    html.gsub("\n", "<br>")
  end

  def sanitize_inline_styles(html)
    return html unless html.include?(" style=")
    doc = Nokogiri::HTML::DocumentFragment.parse(html)
    doc.css("[style]").each do |node|
      cleaned = clean_css_style(node["style"])
      if cleaned.present?
        node["style"] = cleaned
      else
        node.remove_attribute("style")
      end
    end
    doc.to_html
  end

  def clean_css_style(style_value)
    style_value.split(";").filter_map do |declaration|
      next if declaration.strip.empty?
      property, value = declaration.split(":", 2).map(&:strip)
      next unless property && value
      next if property.include?("\\") || value.include?("\\")
      prop = property.downcase
      next unless ALLOWED_CSS_PROPERTIES.include?(prop)
      next if value.match?(/\bexpression\b|\bjavascript\b|url\s*\(/i)
      "#{prop}: #{value}"
    end.join("; ")
  end

  def strip_block_tag_newlines(text)
    text.gsub(BLOCK_TAG_TRAILING_NEWLINE_RE, '\1')
        .gsub(BLOCK_TAG_LEADING_NEWLINE_RE, "")
  end

  def replace_emote_codes(html, large_emotes: false)
    # Only replace emotes in text nodes — skip <code>...</code> blocks and HTML tags
    # so that emote codes inside attributes (e.g. title=":11-aqua-heart:") are preserved.
    # Entities are skipped too, so the ; ending one (&amp;) can't open an emote code.
    registry = EmoteRegistry.current
    lines = emote_pieces(html).slice_after { |_, kind| kind == :break }
    lines.map do |line|
      large = large_emotes && emote_only_line?(line, registry)
      line.map do |piece, kind|
        next piece unless kind == :text
        registry.replace_codes(piece) { |emote| emote_image_tag(emote, large: large) }
      end.join
    end.join
  end

  # Splits HTML into [string, kind] pairs:
  #   :text    to look for emote codes in
  #   :break   a newline or tag that starts a new line
  #   :content code, images and entities, which count as something else on the line
  #   :markup  tags that don't (b, span, ...) and non-breaking spaces
  def emote_pieces(html)
    html.split(EMOTE_SKIP_PATTERN).each_with_index.flat_map do |token, index|
      if index.even?
        token.split(/(\n)/).reject(&:empty?).map { |text| [ text, text == "\n" ? :break : :text ] }
      else
        [ [ token, emote_piece_kind(token) ] ]
      end
    end
  end

  def emote_piece_kind(token)
    case token
    when LINE_BREAK_TAG_PATTERN then :break
    when /\A<(?:code|img)\b/i then :content
    when /\A&(?:nbsp|#160|#xa0);\z/i then :markup
    when /\A&/ then :content
    else :markup
    end
  end

  # Whether a line holds emotes and nothing else but whitespace and markup.
  def emote_only_line?(line, registry)
    count = 0
    only_emotes = line.all? do |piece, kind|
      case kind
      when :content then false
      when :text
        rest = registry.replace_codes(piece) do
          count += 1
          ""
        end
        rest.match?(/\A[[:space:]]*\z/)
      else true
      end
    end
    only_emotes && count.between?(1, LARGE_EMOTE_LIMIT)
  end

  def emote_image_tag(emote, large: false)
    size = large ? 48 : 24
    css_class = large ? "emote-inline emote-inline--large" : "emote-inline"
    '<img src="%s" title="%s" alt="%s" class="%s" width="%d" height="%d" loading="lazy">' % [ emote.src, emote.label, emote.label, css_class, size, size ]
  end

  def convert_spoilers_outside_code(text)
    # Split on <code>...</code> blocks so we only convert ||text|| outside them
    parts = text.split(CODE_BLOCK_PATTERN)
    code_blocks = text.scan(CODE_BLOCK_PATTERN)

    result = parts.map { |part| part.gsub(SPOILER_HINT_PATTERN) { build_spoiler_span(Regexp.last_match) } }
    code_blocks.each_with_index { |block, i| result.insert((i * 2) + 1, block) }
    result.join
  end

  def build_spoiler_span(match)
    hint = match[:pre_hint] || match[:post_hint]
    content = match[:content]
    if hint
      escaped = ERB::Util.html_escape(hint)
      '<span class="spoiler spoiler--with-hint" role="button" tabindex="0" ' \
        "aria-expanded=\"false\" " \
        "aria-label=\"Hidden content: #{escaped}, click to reveal\" " \
        "data-spoiler-hint=\"#{escaped}\">#{content}</span>"
    else
      '<span class="spoiler" role="button" tabindex="0" ' \
        "aria-expanded=\"false\" aria-label=\"Hidden content, click to reveal\">#{content}</span>"
    end
  end
end
