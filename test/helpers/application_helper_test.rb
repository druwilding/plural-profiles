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

  test "preserves simple_format paragraph wrapping" do
    text = "Line one\n\nLine two"
    result = formatted_description(text)
    assert_includes result, "<p>Line one</p>"
    assert_includes result, "<p>Line two</p>"
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
    assert_includes result, "<p>Intro paragraph</p>"
    assert_includes result, "<details>"
    assert_includes result, "<summary>More info</summary>"
    assert_includes result, "Hidden content"
    assert_includes result, "<p>Closing paragraph</p>"
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

  # -- Heart emoji inline replacement --

  test "replaces a valid heart emoji code regardless of case" do
    text = "I love this :11_AQUA_HEART: so much"
    result = formatted_description(text)
    assert_includes result, '<img src="/images/hearts/11_aqua_heart.webp"'
    assert_includes result, 'title="aqua heart"'
    assert_includes result, 'alt="aqua heart"'
    assert_includes result, 'class="heart-inline"'
    assert_not_includes result, ":11_AQUA_HEART:"
  end

  test "replaces a valid heart emoji code with an image" do
    text = "I love this :11_aqua_heart: so much"
    result = formatted_description(text)
    assert_includes result, '<img src="/images/hearts/11_aqua_heart.webp"'
    assert_includes result, 'title="aqua heart"'
    assert_includes result, 'alt="aqua heart"'
    assert_includes result, 'class="heart-inline"'
    assert_not_includes result, ":11_aqua_heart:"
  end

  test "replaces multiple adjacent heart emojis" do
    text = ":11_aqua_heart::12_ocean_heart::13_storm_heart:"
    result = formatted_description(text)
    assert_includes result, '<img src="/images/hearts/11_aqua_heart.webp"'
    assert_includes result, '<img src="/images/hearts/12_ocean_heart.webp"'
    assert_includes result, '<img src="/images/hearts/13_storm_heart.webp"'
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
    text = "hello :36_red_heart: and ||secret|| bye"
    result = formatted_description(text)
    assert_includes result, '<img src="/images/hearts/36_red_heart.webp"'
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

  test "does not convert heart emoji code inside a code block" do
    text = "Use <code>:11_aqua_heart:</code> to show a heart"
    result = formatted_description(text)
    assert_includes result, "<code>:11_aqua_heart:</code>"
    assert_not_includes result, '<img src="/images/hearts/11_aqua_heart.webp"'
  end

  test "converts hearts outside code but not inside" do
    text = ":36_red_heart: and <code>:11_aqua_heart:</code> and :13_storm_heart:"
    result = formatted_description(text)
    assert_includes result, '<img src="/images/hearts/36_red_heart.webp"'
    assert_includes result, '<img src="/images/hearts/13_storm_heart.webp"'
    assert_includes result, "<code>:11_aqua_heart:</code>"
    assert_not_includes result, '<img src="/images/hearts/11_aqua_heart.webp"'
  end

  test "does not replace heart emoji codes inside HTML tag attributes" do
    text = '<span class="spoiler" aria-label=":11_aqua_heart:">:36_red_heart:</span>'
    result = formatted_description(text)
    assert_includes result, 'aria-label=":11_aqua_heart:"'
    assert_includes result, '<img src="/images/hearts/36_red_heart.webp"'
    assert_not_includes result, '<img src="/images/hearts/11_aqua_heart.webp"'
  end
end
