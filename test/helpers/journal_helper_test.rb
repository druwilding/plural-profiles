require "test_helper"

class JournalHelperTest < ActionView::TestCase
  test "a username can wrap after its underscores" do
    assert_equal "example_<wbr>journal", journal_wrappable_username("example_journal")
    assert_equal "plain", journal_wrappable_username("plain")
  end
end
