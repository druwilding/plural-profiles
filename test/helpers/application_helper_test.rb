require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
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
end
