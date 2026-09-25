require "test_helper"

class EmoteSetTest < ActiveSupport::TestCase
  test "requires a name" do
    emote_set = EmoteSet.new(name: " ")
    assert_not emote_set.valid?
    assert_includes emote_set.errors[:name], "can't be blank"
  end

  test "site-wide set names are unique" do
    emote_set = EmoteSet.new(name: "hearts")
    assert_not emote_set.valid?
    assert_includes emote_set.errors[:name], "has already been taken"
  end

  test "a set with emotes can't be destroyed" do
    emote_set = emote_sets(:hearts)
    assert_not emote_set.destroy
    assert emote_set.persisted?
  end
end
