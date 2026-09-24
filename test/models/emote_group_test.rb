require "test_helper"

class EmoteGroupTest < ActiveSupport::TestCase
  test "requires a name" do
    group = EmoteGroup.new(name: " ")
    assert_not group.valid?
    assert_includes group.errors[:name], "can't be blank"
  end

  test "site-wide group names are unique" do
    group = EmoteGroup.new(name: "hearts")
    assert_not group.valid?
    assert_includes group.errors[:name], "has already been taken"
  end

  test "a group with emotes can't be destroyed" do
    group = emote_groups(:hearts)
    assert_not group.destroy
    assert group.persisted?
  end
end
