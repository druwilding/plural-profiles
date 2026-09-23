require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  SPOILER_OPEN = '<span class="spoiler" role="button" tabindex="0" ' \
    'aria-expanded="false" aria-label="Hidden content, click to reveal">'

  test "allows details and summary tags" do
    text = "<details><summary>Title</summary>Content</details>"
    result = formatted_description(text)
    assert_includes result, "<details>"
    assert_includes result, "<summary>"
    assert_includes result, "Title"
    assert_includes result, "Content"
    assert_includes result, "</details>"
  end

  test "allows the open attribute on details" do
    text = "<details open><summary>Title</summary>Content</details>"
    result = formatted_description(text)
    assert_includes result, "<details"
    assert_match(/open/, result)
  end

  test "newlines become br tags" do
    text = "Line one\n\nLine two"
    result = formatted_description(text)
    assert_includes result, "Line one<br><br>Line two"
  end

  test "strips script tags" do
    text = "<script>alert('xss')</script>Safe text"
    result = formatted_description(text)
    assert_not_includes result, "<script>"
    assert_not_includes result, "</script>"
    assert_includes result, "Safe text"
  end

  test "strips event handler attributes" do
    text = "<details onmouseover=\"alert('xss')\"><summary>Title</summary></details>"
    result = formatted_description(text)
    assert_not_includes result, "onmouseover"
    assert_not_includes result, "alert"
    assert_includes result, "<details>"
  end

  test "strips iframe tags" do
    text = "<iframe src=\"https://evil.com\"></iframe>Safe text"
    result = formatted_description(text)
    assert_not_includes result, "<iframe"
    assert_includes result, "Safe text"
  end

  test "details and summary work alongside plain text" do
    text = "Intro paragraph\n\n<details><summary>More info</summary>Hidden content</details>\n\nClosing paragraph"
    result = formatted_description(text)
    assert_includes result, "Intro paragraph<br><br><details>"
    assert_includes result, "<summary>More info</summary>"
    assert_includes result, "Hidden content"
    assert_includes result, "</details><br><br>Closing paragraph"
  end

  test "details content with blank lines stays inside the details element" do
    text = "<details><summary>Title</summary>\n\ncontent line 1\n\ncontent line 2\n\n</details>"
    result = formatted_description(text)
    assert_includes result, "<details>"
    assert_includes result, "<summary>Title</summary>"
    assert_match(/<details>.*content line 1.*content line 2.*<\/details>/m, result)
  end

  test "inline tags like i span across blank lines" do
    text = "<i>verse one\n\nverse two</i>"
    result = formatted_description(text)
    assert_match(/<i>.*verse one.*verse two.*<\/i>/m, result)
  end

  # -- Spoiler syntax (||text||) --

  test "converts double-pipe syntax to spoiler span" do
    text = "the secret is ||hidden content|| here"
    result = formatted_description(text)
    assert_includes result, "#{SPOILER_OPEN}hidden content</span>"
  end

  test "converts multiple spoilers in one text" do
    text = "||first|| and ||second||"
    result = formatted_description(text)
    assert_includes result, "#{SPOILER_OPEN}first</span>"
    assert_includes result, "#{SPOILER_OPEN}second</span>"
  end

  test "does not convert single pipes" do
    text = "a | b | c"
    result = formatted_description(text)
    assert_not_includes result, "spoiler"
    assert_includes result, "a | b | c"
  end

  test "does not convert empty double pipes" do
    text = "nothing |||| here"
    result = formatted_description(text)
    assert_not_includes result, "#{SPOILER_OPEN}</span>"
    assert_includes result, "||||"
  end

  test "spoiler works alongside details tags" do
    text = "<details><summary>Info</summary>||secret||</details>"
    result = formatted_description(text)
    assert_includes result, "<details>"
    assert_includes result, "#{SPOILER_OPEN}secret</span>"
  end

  test "does not convert double pipes inside code tags" do
    text = "Use <code>||text||</code> to hide text"
    result = formatted_description(text)
    assert_includes result, "<code>||text||</code>"
    assert_not_includes result, "#{SPOILER_OPEN}text</span>"
  end

  test "converts spoilers outside code but not inside" do
    text = "||hidden|| and <code>||visible||</code> and ||also hidden||"
    result = formatted_description(text)
    assert_includes result, "#{SPOILER_OPEN}hidden</span>"
    assert_includes result, "#{SPOILER_OPEN}also hidden</span>"
    assert_includes result, "<code>||visible||</code>"
  end

  test "converts multiline spoilers" do
    text = "||line one\nline two||"
    result = formatted_description(text)
    assert_includes result, "#{SPOILER_OPEN}line one"
    assert_includes result, "line two</span>"
  end

  test "disallows dangerous content inside spoilers" do
    text = "||<script>alert('xss')</script>||"
    result = formatted_description(text)
    assert_includes result, SPOILER_OPEN
    assert_not_includes result, "<script"
  end

  test "handles nested spoilers input" do
    text = "||outer ||inner|| outer||"
    result = formatted_description(text)
    assert_includes result, "outer"
    assert_includes result, "inner"
    assert_includes result, "spoiler"
  end

  test "escapes special HTML characters inside spoilers" do
    text = '||<>&"||'
    result = formatted_description(text)
    assert_includes result, SPOILER_OPEN
    assert_not_includes result, '||<>&"||'
    assert_includes result, "&lt;&gt;&amp;\""
  end

  test "handles spoilers spanning multiple lines" do
    text = "start ||multi\nline|| end"
    result = formatted_description(text)
    assert_includes result, "multi"
    assert_includes result, "line"
    assert_includes result, "spoiler"
  end

  test "handles spoilers containing markdown-like content" do
    text = "||**bold** and http://example.com||"
    result = formatted_description(text)
    assert_includes result, SPOILER_OPEN
    assert_includes result, "bold"
    assert_includes result, "http://example.com"
  end

  # -- Spoiler accessibility attributes --

  test "spoiler span includes accessibility attributes" do
    text = "||secret||"
    result = formatted_description(text)
    assert_includes result, 'role="button"'
    assert_includes result, 'tabindex="0"'
    assert_includes result, 'aria-expanded="false"'
    assert_includes result, 'aria-label="Hidden content, click to reveal"'
  end

  # -- Spoiler hint syntax ([hint]||text|| or ||text||[hint]) --

  SPOILER_HINT_OPEN = '<span class="spoiler spoiler--with-hint" role="button" tabindex="0" ' \
    'aria-expanded="false" aria-label="Hidden content: the hint, click to reveal" ' \
    'data-spoiler-hint="the hint">'

  test "hint after spoiler produces spoiler--with-hint span" do
    text = "||secret||[the hint]"
    result = formatted_description(text)
    assert_includes result, "#{SPOILER_HINT_OPEN}secret</span>"
    assert_not_includes result, "[the hint]"
  end

  test "hint before spoiler produces the same output" do
    text = "[the hint]||secret||"
    result = formatted_description(text)
    assert_includes result, "#{SPOILER_HINT_OPEN}secret</span>"
    assert_not_includes result, "[the hint]"
  end

  test "both orderings produce identical HTML" do
    result_after  = formatted_description("||secret||[the hint]")
    result_before = formatted_description("[the hint]||secret||")
    assert_equal result_after, result_before
  end

  test "spoiler without hint is unchanged by hint syntax" do
    text = "||secret||"
    result = formatted_description(text)
    assert_includes result, "#{SPOILER_OPEN}secret</span>"
    assert_not_includes result, "spoiler--with-hint"
  end

  test "hint aria-label incorporates hint text" do
    text = "||hidden||[it is a password]"
    result = formatted_description(text)
    assert_includes result, 'aria-label="Hidden content: it is a password, click to reveal"'
  end

  test "hint text is stored in data-spoiler-hint attribute" do
    text = "||hidden||[it is a password]"
    result = formatted_description(text)
    assert_includes result, 'data-spoiler-hint="it is a password"'
  end

  test "hint text is HTML-escaped in attributes" do
    # The sanitiser (Nokogiri) decode/re-serialises attribute values:
    # & → &amp; and " → &quot; are preserved; < and > become literal characters
    # (still safe — CSS content: attr() treats them as plain text, not markup).
    text = '||secret||[<b> & "quotes"]'
    result = formatted_description(text)
    assert_includes result, 'data-spoiler-hint="<b> &amp; &quot;quotes&quot;"'
  end

  test "hint with special chars appears correctly in aria-label" do
    text = '||secret||[<b> & "quotes"]'
    result = formatted_description(text)
    assert_includes result, 'aria-label="Hidden content: <b> &amp; &quot;quotes&quot;, click to reveal"'
  end

  test "hint does not leak into visible spoiler content" do
    text = "||the secret||[this is the hint]"
    result = formatted_description(text)
    assert_includes result, ">the secret</span>"
    assert_not_includes result, ">this is the hint"
  end

  test "multiple spoilers can each have their own hint" do
    text = "||first||[hint one] and ||second||[hint two]"
    result = formatted_description(text)
    assert_includes result, 'data-spoiler-hint="hint one"'
    assert_includes result, 'data-spoiler-hint="hint two"'
    assert_includes result, ">first</span>"
    assert_includes result, ">second</span>"
  end

  test "mix of hinted and plain spoilers in same text" do
    text = "||plain|| and ||hinted||[a clue]"
    result = formatted_description(text)
    assert_includes result, "#{SPOILER_OPEN}plain</span>"
    assert_includes result, 'data-spoiler-hint="a clue"'
    assert_includes result, ">hinted</span>"
  end

  test "does not convert hint syntax inside code tags" do
    text = "Use <code>||text||[hint]</code> for spoilers"
    result = formatted_description(text)
    assert_includes result, "<code>||text||[hint]</code>"
    assert_not_includes result, "spoiler--with-hint"
  end

  test "hint spoiler with whitespace between hint and pipes" do
    text = "[hint text] ||secret||"
    result = formatted_description(text)
    assert_includes result, 'data-spoiler-hint="hint text"'
  end

  # -- Heart emoji inline replacement --

  test "replaces a valid heart emoji code regardless of case" do
    text = "I love this :11_AQUA_HEART: so much"
    result = formatted_description(text)
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("aqua_heart")}\""
    assert_includes result, 'title="aqua heart"'
    assert_includes result, 'alt="aqua heart"'
    assert_includes result, 'class="heart-inline emote-inline"'
    assert_not_includes result, ":11_AQUA_HEART:"
  end

  test "replaces a valid heart emoji code with an image" do
    text = "I love this :11_aqua_heart: so much"
    result = formatted_description(text)
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("aqua_heart")}\""
    assert_includes result, 'title="aqua heart"'
    assert_includes result, 'alt="aqua heart"'
    assert_includes result, 'class="heart-inline emote-inline"'
    assert_not_includes result, ":11_aqua_heart:"
  end

  test "replaces multiple adjacent heart emojis" do
    text = ":11_aqua_heart::12_ocean_heart::13_storm_heart:"
    result = formatted_description(text)
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("aqua_heart")}\""
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("ocean_heart")}\""
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("storm_heart")}\""
  end

  test "leaves unknown heart codes as plain text" do
    text = "look :99_fake_heart: here"
    result = formatted_description(text)
    assert_includes result, ":99_fake_heart:"
    assert_not_includes result, "<img"
  end

  test "leaves non-heart colon expressions as plain text" do
    text = "time is :noon: already"
    result = formatted_description(text)
    assert_includes result, ":noon:"
    assert_not_includes result, "<img"
  end

  test "mixes heart emojis with regular text and spoilers" do
    text = "hello :40_red_heart: and ||secret|| bye"
    result = formatted_description(text)
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("red_heart")}\""
    assert_includes result, SPOILER_OPEN
  end

  test "heart emoji alt text strips number prefix and uses spaces" do
    text = ":01_dewdrop_heart:"
    result = formatted_description(text)
    assert_includes result, 'alt="dewdrop heart"'
  end

  test "heart emoji alt text handles cadbury style prefix" do
    text = ":50cadbury_heart:"
    result = formatted_description(text)
    assert_includes result, 'alt="cadbury heart"'
  end

  test "replaces cadbury heart code regardless of number prefix style" do
    [ "50cadbury_heart", "51cadbury_heart", "50_cadbury_heart" ].each do |code|
      result = formatted_description(":#{code}:")
      assert_includes result, "<img src=\"#{HeartEmoji.image_path("cadbury_heart")}\"", "expected #{code} to resolve"
      assert_includes result, 'alt="cadbury heart"'
    end
  end

  test "replaces heart code given as a bare name without a number prefix" do
    text = "I love this :aqua_heart: so much"
    result = formatted_description(text)
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("aqua_heart")}\""
    assert_includes result, 'title="aqua heart"'
    assert_includes result, 'alt="aqua heart"'
    assert_not_includes result, ":aqua_heart:"
  end

  test "replaces cadbury heart code" do
    text = "here is :cadbury_heart: for you"
    result = formatted_description(text)
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("cadbury_heart")}\""
    assert_includes result, 'alt="cadbury heart"'
    assert_not_includes result, ":cadbury_heart:"
  end

  test "replaces a heart code that still carries an old number prefix" do
    text = "here is :25_shadow_heart: even though it's now 26"
    result = formatted_description(text)
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("shadow_heart")}\""
    assert_includes result, 'alt="shadow heart"'
    assert_not_includes result, ":25_shadow_heart:"
  end

  test "replaces bare heart code case-insensitively" do
    text = ":AQUA_HEART:"
    result = formatted_description(text)
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("aqua_heart")}\""
    assert_not_includes result, ":AQUA_HEART:"
  end

  test "replaces heart code delimited by semicolons" do
    text = "here is ;cadbury_heart; for you"
    result = formatted_description(text)
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("cadbury_heart")}\""
    assert_not_includes result, ";cadbury_heart;"
  end

  test "replaces heart code with hyphens instead of underscores" do
    text = "here is :cadbury-heart: for you"
    result = formatted_description(text)
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("cadbury_heart")}\""
    assert_not_includes result, ":cadbury-heart:"
  end

  test "replaces heart code with mismatched delimiters and separators" do
    [ ";cadbury-heart;", ":cadbury_heart;", ";cadbury-heart:", ":cadbury-heart;" ].each do |code|
      result = formatted_description(code)
      assert_includes result, "<img src=\"#{HeartEmoji.image_path("cadbury_heart")}\"", "expected #{code} to resolve"
    end
  end

  test "does not convert heart emoji code inside a code block" do
    text = "Use <code>:11_aqua_heart:</code> to show a heart"
    result = formatted_description(text)
    assert_includes result, "<code>:11_aqua_heart:</code>"
    assert_not_includes result, "<img src=\"#{HeartEmoji.image_path("aqua_heart")}\""
  end

  test "converts hearts outside code but not inside" do
    text = ":40_red_heart: and <code>:11_aqua_heart:</code> and :13_storm_heart:"
    result = formatted_description(text)
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("red_heart")}\""
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("storm_heart")}\""
    assert_includes result, "<code>:11_aqua_heart:</code>"
    assert_not_includes result, "<img src=\"#{HeartEmoji.image_path("aqua_heart")}\""
  end

  test "does not replace heart emoji codes inside HTML tag attributes" do
    text = '<span class="spoiler" aria-label=":11_aqua_heart:">:40_red_heart:</span>'
    result = formatted_description(text)
    assert_includes result, 'aria-label=":11_aqua_heart:"'
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("red_heart")}\""
    assert_not_includes result, "<img src=\"#{HeartEmoji.image_path("aqua_heart")}\""
  end

  test "replaces an emote code that doesn't end in _heart" do
    emote = Emote.new(emote_group: emote_groups(:hearts), name: "100")
    emote.image.attach(io: StringIO.new(png_bytes(8, 8)), filename: "100.png", content_type: "image/png")
    emote.save!

    result = formatted_inline("that's :100:!")
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("100")}\""
    assert_includes result, 'class="heart-inline emote-inline"'
    assert_not_includes result, ":100:"
  end

  test "replaces an emote typed by its name" do
    result = formatted_inline(":02_spring_heart:")
    assert_includes result, "<img src=\"#{HeartEmoji.image_path("spring_heart")}\""
    assert_includes result, 'alt="spring heart"'
  end

  test "an unknown code doesn't stop the next emote from rendering" do
    result = formatted_inline("see you at 12:30:red_heart:")
    assert_includes result, "see you at 12:30<img src=\"#{HeartEmoji.image_path("red_heart")}\""
  end

  test "the semicolon ending an HTML entity doesn't open an emote code" do
    assert_equal "&amp;red_heart;", formatted_inline("&amp;red_heart;")
    result = formatted_inline("Tom & Jerry;red_heart;")
    assert_includes result, "Tom &amp; Jerry<img src=\"#{HeartEmoji.image_path("red_heart")}\""
  end

  test "leaves unknown codes as typed" do
    assert_equal "a :fake_heart: b :note:", formatted_inline("a :fake_heart: b :note:")
  end

  test "plain_field replaces emotes with their group's plain text symbol" do
    other = EmoteGroup.create!(name: "Other", position: 1, plain_text: "★")
    emote = Emote.new(emote_group: other, name: "100")
    emote.image.attach(io: StringIO.new(png_bytes(8, 8)), filename: "100.png", content_type: "image/png")
    emote.save!

    assert_equal "Hello ♥ and ★", plain_field("Hello :11_aqua_heart: and ;100;")
  end

  test "plain_field leaves unknown codes as typed" do
    assert_equal "Ratio 3:2 :fake_heart:", plain_field("Ratio 3:2 :fake_heart:")
  end

  # -- Multiple blank lines --

  test "two newlines produce a blank line" do
    result = formatted_description("a\n\nb")
    assert_includes result, "a<br><br>b"
  end

  test "three newlines produce extra spacing" do
    result = formatted_description("a\n\n\nb")
    assert_includes result, "a<br><br><br>b"
  end

  test "four newlines produce even more spacing" do
    result = formatted_description("a\n\n\n\nb")
    assert_includes result, "a<br><br><br><br>b"
  end

  test "three CRLF newlines produce extra spacing" do
    result = formatted_description("a\r\n\r\n\r\nb")
    assert_includes result, "a<br><br><br>b"
  end

  test "extra blank lines between three blocks are preserved" do
    result = formatted_description("first\n\n\nsecond\n\n\n\nthird")
    assert_includes result, "first<br><br><br>second"
    assert_includes result, "second<br><br><br><br>third"
  end

  # -- Table support --

  test "allows table, tr, td tags" do
    text = "<table><tr><td>cell one</td><td>cell two</td></tr></table>"
    result = formatted_description(text)
    assert_includes result, "<table>"
    assert_includes result, "<tr>"
    assert_includes result, "<td>cell one</td>"
    assert_includes result, "<td>cell two</td>"
  end

  test "allows thead, tbody, tfoot, th tags" do
    text = "<table><thead><tr><th>Header</th></tr></thead><tbody><tr><td>Body</td></tr></tbody><tfoot><tr><td>Footer</td></tr></tfoot></table>"
    result = formatted_description(text)
    assert_includes result, "<thead>"
    assert_includes result, "<th>Header</th>"
    assert_includes result, "<tbody>"
    assert_includes result, "<td>Body</td>"
    assert_includes result, "<tfoot>"
    assert_includes result, "<td>Footer</td>"
  end

  test "allows colspan and rowspan attributes on td" do
    text = '<table><tr><td colspan="2">wide</td></tr><tr><td rowspan="2">tall</td><td>other</td></tr></table>'
    result = formatted_description(text)
    assert_includes result, 'colspan="2"'
    assert_includes result, 'rowspan="2"'
  end

  test "multiple newlines between table structural tags do not produce br inside table" do
    text = "<table>\n\n\n<tr>\n\n\n<td>content</td>\n\n\n</tr>\n\n\n</table>"
    result = formatted_description(text)
    assert_includes result, "<table>"
    assert_includes result, "<tr>"
    assert_includes result, "<td>content</td>"
    refute_match(/<t(?:able|r|d|head|body|foot)[^>]*>.*?<br/m, result)
  end

  test "strips newlines between table structural tags before formatting" do
    text = "<table>\n<tr>\n<td>content</td>\n</tr>\n</table>"
    result = formatted_description(text)
    assert_includes result, "<table>"
    assert_includes result, "<tr>"
    assert_includes result, "<td>content</td>"
    # Newlines between structural tags must not become <br> inside the table
    refute_match(/<t(?:able|r|d|head|body|foot)[^>]*>.*?<br/m, result)
  end

  test "newlines around non-table block elements become br tags" do
    text = "Before\n\n<div class=\"img-row\">content</div>\n\nAfter"
    result = formatted_description(text)
    assert_includes result, "Before<br><br><div"
    assert_includes result, "</div><br><br>After"
  end

  # -- Inline style sanitization --

  test "allows float in style attribute" do
    text = '<img src="x.jpg" alt="x" style="float: left;">'
    result = formatted_description(text)
    assert_includes result, 'style="float: left"'
  end

  test "allows width and height in style attribute" do
    text = '<img src="x.jpg" alt="x" style="width: 100px; height: 100px;">'
    result = formatted_description(text)
    assert_includes result, "width: 100px"
    assert_includes result, "height: 100px"
  end

  test "allows padding in style attribute" do
    text = '<img src="x.jpg" alt="x" style="padding: 10px;">'
    result = formatted_description(text)
    assert_includes result, "padding: 10px"
  end

  test "allows margin in style attribute" do
    text = '<p style="margin: 0 1em;">text</p>'
    result = formatted_description(text)
    assert_includes result, "margin: 0 1em"
  end

  test "allows text-align in style attribute" do
    text = '<p style="text-align: center;">text</p>'
    result = formatted_description(text)
    assert_includes result, "text-align: center"
  end

  test "allows border-radius in style attribute" do
    text = '<img src="x.jpg" alt="x" style="border-radius: 50%;">'
    result = formatted_description(text)
    assert_includes result, "border-radius: 50%"
  end

  test "allows max-width in style attribute" do
    text = '<img src="x.jpg" alt="x" style="max-width: 200px;">'
    result = formatted_description(text)
    assert_includes result, "max-width: 200px"
  end

  test "strips disallowed color property from style" do
    text = '<p style="color: red;">text</p>'
    result = formatted_description(text)
    assert_not_includes result, "color"
    assert_includes result, "text"
  end

  test "strips disallowed background-color from style" do
    text = '<p style="background-color: white; color: white;">hidden</p>'
    result = formatted_description(text)
    assert_not_includes result, "background-color"
    assert_not_includes result, "color"
    assert_includes result, "hidden"
  end

  test "strips disallowed position from style" do
    text = '<div style="position: fixed; top: 0;">overlay</div>'
    result = formatted_description(text)
    assert_not_includes result, "position"
    assert_not_includes result, "top"
    assert_includes result, "overlay"
  end

  test "keeps allowed properties and strips disallowed ones in the same style" do
    text = '<img src="x.jpg" alt="x" style="float: left; color: red; width: 100px; position: absolute;">'
    result = formatted_description(text)
    assert_includes result, "float: left"
    assert_includes result, "width: 100px"
    assert_not_includes result, "color"
    assert_not_includes result, "position"
  end

  test "removes style attribute entirely when all properties are stripped" do
    text = '<p style="color: red; position: fixed;">text</p>'
    result = formatted_description(text)
    assert_not_includes result, "style="
    assert_includes result, "text"
  end

  test "strips expression() from style values" do
    text = '<p style="width: expression(alert(1));">text</p>'
    result = formatted_description(text)
    assert_not_includes result, "expression"
    assert_includes result, "text"
  end

  test "strips url() from style values" do
    text = '<p style="padding: url(https://evil.com);">text</p>'
    result = formatted_description(text)
    assert_not_includes result, "url("
    assert_includes result, "text"
  end

  test "strips CSS escape sequences from style values" do
    text = '<p style="padding: u\\72l(https://evil.com);">text</p>'
    result = formatted_description(text)
    assert_not_includes result, "url"
    assert_not_includes result, "evil"
    assert_includes result, "text"
  end

  test "strips CSS escape sequences from property names" do
    text = '<p style="\\63olor: red;">text</p>'
    result = formatted_description(text)
    assert_not_includes result, "color"
    assert_not_includes result, "red"
    assert_includes result, "text"
  end

  test "normalises property names to lowercase" do
    text = '<img src="x.jpg" alt="x" style="Float: left; WIDTH: 100px;">'
    result = formatted_description(text)
    assert_includes result, "float: left"
    assert_includes result, "width: 100px"
    assert_not_includes result, "Float"
    assert_not_includes result, "WIDTH"
  end

  test "allows alt, width and height as HTML attributes on img" do
    text = '<img src="x.jpg" alt="a photo" width="100" height="100">'
    result = formatted_description(text)
    assert_includes result, 'alt="a photo"'
    assert_includes result, 'width="100"'
    assert_includes result, 'height="100"'
  end

  test "float-left class still works alongside style attribute" do
    text = '<img src="x.jpg" alt="x" class="float-left" width="100" height="100">'
    result = formatted_description(text)
    assert_includes result, 'class="float-left"'
    assert_includes result, 'width="100"'
  end

  # -- avatar_shape_class --

  test "avatar_shape_class uses the record's own shape by default" do
    record = Struct.new(:avatar_shape).new("square")
    assert_equal "avatar--square", avatar_shape_class(record)
  end

  test "avatar_shape_class shape: override wins over the record's own shape" do
    record = Struct.new(:avatar_shape).new("square")
    assert_equal "avatar--circle", avatar_shape_class(record, shape: "circle")
  end

  # -- chat_avatar_for / chat_avatar_alt_text_for / chat_avatar_shape_for --

  test "chat_avatar_for falls back to the main avatar when no mini_profile_avatar is attached" do
    profile = profiles(:alice)
    assert_not profile.mini_profile_avatar.attached?
    assert_equal profile.avatar, chat_avatar_for(profile)
  end

  test "chat_avatar_for falls back to the main avatar when inherited even if a mini_profile_avatar happens to be attached" do
    profile = profiles(:alice)
    profile.mini_profile_avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert profile.mini_profile_avatar_inherited?
    assert_equal profile.avatar, chat_avatar_for(profile)
  end

  test "chat_avatar_for uses the mini_profile_avatar once not inherited and one is attached" do
    profile = profiles(:alice)
    profile.update!(mini_profile_avatar_inherited: false)
    profile.mini_profile_avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert_equal profile.mini_profile_avatar, chat_avatar_for(profile)
  end

  test "chat_avatar_for falls back to the main avatar when not inherited but nothing has been uploaded" do
    profile = profiles(:alice)
    profile.update!(mini_profile_avatar_inherited: false)
    assert_not profile.mini_profile_avatar.attached?
    assert_equal profile.avatar, chat_avatar_for(profile)
  end

  test "chat_avatar_shape_for falls back to avatar_shape when inherited" do
    profile = profiles(:alice)
    profile.update!(avatar_shape: "square", mini_profile_avatar_shape: "circle")
    assert_equal "square", chat_avatar_shape_for(profile)
  end

  test "chat_avatar_shape_for uses the mini_profile_avatar_shape once not inherited" do
    profile = profiles(:alice)
    profile.update!(avatar_shape: "square", mini_profile_avatar_shape: "circle")
    profile.mini_profile_avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    profile.update!(mini_profile_avatar_inherited: false)
    assert_equal "circle", chat_avatar_shape_for(profile)
  end

  test "chat_avatar_shape_for honors an overridden shape even without uploading a replacement image" do
    profile = profiles(:alice)
    profile.update!(avatar_shape: "square", mini_profile_avatar_shape: "circle", mini_profile_avatar_inherited: false)
    assert_not profile.mini_profile_avatar.attached?
    assert_equal "circle", chat_avatar_shape_for(profile)
    assert_equal profile.avatar, chat_avatar_for(profile)
  end

  test "chat_avatar_alt_text_for falls back to avatar_alt_text when inherited" do
    profile = profiles(:alice)
    profile.update!(avatar_alt_text: "Alice's main avatar")
    assert_equal "Alice's main avatar", chat_avatar_alt_text_for(profile)
  end

  test "chat_avatar_alt_text_for uses mini_profile_avatar_alt_text once not inherited" do
    profile = profiles(:alice)
    profile.update!(avatar_alt_text: "Alice's main avatar", mini_profile_avatar_alt_text: "Alice's chat avatar",
                     mini_profile_avatar_inherited: false)
    profile.mini_profile_avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert_equal "Alice's chat avatar", chat_avatar_alt_text_for(profile)
  end

  test "full floating image with text works as intended" do
    text = '<p><img src="x.jpg" alt="photo" style="float:left; width:100px;height:100px; padding:10px;">Some text alongside</p>'
    result = formatted_description(text)
    # Nokogiri normalises declarations to "property: value" (space after colon)
    assert_includes result, 'alt="photo"'
    assert_includes result, "float: left"
    assert_includes result, "width: 100px"
    assert_includes result, "height: 100px"
    assert_includes result, "padding: 10px"
    assert_includes result, "Some text alongside"
  end
  # -- Heart input --

  test "heart_emojis_json_tag lists every heart in order" do
    script = Nokogiri::HTML::DocumentFragment.parse(heart_emojis_json_tag).at_css("script#heart-emojis[type='application/json']")
    assert script, "expected a JSON script tag with id heart-emojis"

    hearts = JSON.parse(script.text)
    assert_equal HeartEmoji.all, hearts.map { |heart| heart["name"] }
    assert_equal(
      { "name" => "abyss_heart", "label" => "abyss heart", "src" => HeartEmoji.image_path("abyss_heart"), "code" => ":abyss_heart:" },
      hearts.find { |heart| heart["name"] == "abyss_heart" }
    )
  end

  test "heart_field wraps a text field with a hidden heart picker button" do
    form = ActionView::Helpers::FormBuilder.new(:profile, Profile.new(subtitle: "the creative one"), self, {})
    wrapper = Nokogiri::HTML::DocumentFragment.parse(heart_field(form, :subtitle)).at_css(".heart-input")

    assert_includes wrapper["class"], "heart-input--line"
    assert_equal "heart-input", wrapper["data-controller"]
    assert_equal "below", wrapper["data-heart-input-placement-value"]

    field = wrapper.at_css("input#profile_subtitle[type='text'][name='profile[subtitle]']")
    assert field, "expected the field to keep its normal id and name"
    assert_equal "the creative one", field["value"]
    assert_equal "field", field["data-heart-input-target"]

    button = wrapper.at_css("button.heart-input__button")
    assert_equal "button", button["type"]
    assert button.key?("hidden"), "expected the button to stay hidden until JS connects"
    assert_equal "Insert a heart", button["aria-label"]
    assert_equal "heart-input#openPicker", button["data-action"]
    assert button.at_css("svg[aria-hidden='true']")
  end

  test "heart_field renders a textarea and merges data onto the field" do
    form = ActionView::Helpers::FormBuilder.new(:chat_message, Chat::Message.new, self, {})
    html = heart_field(form, :body, as: :text_area, menu_placement: "above", rows: 1,
      data: { "composer-target": "textarea", action: "keydown->composer#submitOnEnter" })
    wrapper = Nokogiri::HTML::DocumentFragment.parse(html).at_css(".heart-input")

    assert_includes wrapper["class"], "heart-input--area"
    assert_equal "above", wrapper["data-heart-input-placement-value"]

    field = wrapper.at_css("textarea#chat_message_body[rows='1']")
    assert field
    assert_equal "textarea", field["data-composer-target"]
    assert_equal "keydown->composer#submitOnEnter", field["data-action"]
    assert_equal "field", field["data-heart-input-target"]
  end
end
