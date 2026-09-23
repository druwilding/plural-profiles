require "test_helper"

class EmoteGroupTest < ActiveSupport::TestCase
  test "requires a plain text symbol" do
    group = EmoteGroup.new(name: "Other", plain_text: " ")
    assert_not group.valid?
    assert_includes group.errors[:plain_text], "can't be blank"
  end

  test "plain text counts a multi-codepoint emoji as one character" do
    assert EmoteGroup.new(name: "Other", plain_text: "🏳️‍🌈").valid?
    assert_not EmoteGroup.new(name: "Other", plain_text: "♥♥♥♥♥").valid?
  end

  test "site-wide group names are unique" do
    group = EmoteGroup.new(name: "hearts", plain_text: "♥")
    assert_not group.valid?
    assert_includes group.errors[:name], "has already been taken"
  end

  test "a group with emotes can't be destroyed" do
    group = emote_groups(:hearts)
    assert_not group.destroy
    assert group.persisted?
  end
end
