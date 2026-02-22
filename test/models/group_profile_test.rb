require "test_helper"

class GroupProfileTest < ActiveSupport::TestCase
  test "links profile to group" do
    gp = group_profiles(:alice_in_friends)
    assert_equal groups(:friends), gp.group
    assert_equal profiles(:alice), gp.profile
  end

  test "prevents duplicate profile in same group" do
    duplicate = GroupProfile.new(
      group: groups(:friends),
      profile: profiles(:alice)
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:profile_id], "has already been taken"
  end

  test "allows same profile in different groups" do
    gp = GroupProfile.new(
      group: groups(:family),
      profile: profiles(:alice)
    )
    assert gp.valid?
  end
end
