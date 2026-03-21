require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "requires email_address" do
    user = User.new(password: "N3wUs3r!S1gnup#2026", password_confirmation: "N3wUs3r!S1gnup#2026")
    assert_not user.valid?
    assert_includes user.errors[:email_address], "can't be blank"
  end

  test "requires unique email_address" do
    user = User.new(
      email_address: users(:one).email_address,
      password: "N3wUs3r!S1gnup#2026",
      password_confirmation: "N3wUs3r!S1gnup#2026"
    )
    assert_not user.valid?
    assert_includes user.errors[:email_address], "has already been taken"
  end

  test "requires valid email format" do
    user = User.new(email_address: "not-an-email", password: "N3wUs3r!S1gnup#2026", password_confirmation: "N3wUs3r!S1gnup#2026")
    assert_not user.valid?
    assert_includes user.errors[:email_address], "is invalid"
  end

  test "requires password with minimum length" do
    user = User.new(email_address: "new@example.com", password: "short", password_confirmation: "short")
    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 8 characters)"
  end

  test "has many profiles" do
    user = users(:one)
    assert_includes user.profiles, profiles(:alice)
    assert_includes user.profiles, profiles(:bob)
  end

  test "has many groups" do
    user = users(:one)
    assert_includes user.groups, groups(:friends)
  end

  test "destroying user destroys associated profiles" do
    user = users(:one)
    profile_count = user.profiles.count
    assert_difference("Profile.count", -profile_count) { user.destroy }
  end

  test "destroying user destroys associated groups" do
    user = users(:one)
    group_count = user.groups.count
    assert_difference("Group.count", -group_count) { user.destroy }
  end

  # -- Deactivation --

  test "deactivated? is false for a normal user" do
    assert_not users(:one).deactivated?
  end

  test "deactivated? is true when deactivated_at is set" do
    user = users(:one)
    user.update_column(:deactivated_at, Time.current)
    assert user.deactivated?
  end

  test "deactivate! sets deactivated_at" do
    user = users(:one)
    assert_nil user.deactivated_at
    user.deactivate!
    assert_not_nil user.reload.deactivated_at
  end

  test "deactivate! destroys all sessions" do
    user = users(:one)
    user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    user.sessions.create!(user_agent: "test2", ip_address: "127.0.0.2")
    assert user.sessions.any?
    user.deactivate!
    assert user.sessions.reload.empty?
  end

  # -- Account name (username) --

  test "account name is optional" do
    user = users(:two)
    user.username = nil
    assert user.valid?
  end

  test "account name is normalised to lowercase" do
    user = users(:two)
    user.username = "  FooBar  "
    user.valid?
    assert_equal "foobar", user.username
  end

  test "blank account name becomes nil" do
    user = users(:two)
    user.username = "   "
    user.valid?
    assert_nil user.username
  end

  test "valid account names are accepted" do
    user = users(:two)
    %w[ab abc abc123 foo-bar foo_bar a1 a-b a_b abcdefghijklmnopqrst1234].each do |name|
      user.username = name
      assert user.valid?, "Expected '#{name}' to be valid but got: #{user.errors.full_messages}"
    end
  end

  test "single character account name is invalid" do
    user = users(:two)
    user.username = "a"
    assert_not user.valid?
    assert user.errors[:username].any?
  end

  test "account name with leading underscore is invalid" do
    user = users(:two)
    user.username = "_abc"
    assert_not user.valid?
  end

  test "account name with trailing hyphen is invalid" do
    user = users(:two)
    user.username = "abc-"
    assert_not user.valid?
  end

  test "account name with consecutive underscores is invalid" do
    user = users(:two)
    user.username = "a__b"
    assert_not user.valid?
  end

  test "account name with consecutive hyphens is invalid" do
    user = users(:two)
    user.username = "a--b"
    assert_not user.valid?
  end

  test "account name with mixed consecutive special chars is invalid" do
    user = users(:two)
    user.username = "a-_b"
    assert_not user.valid?
  end

  test "account name with spaces is invalid" do
    user = users(:two)
    user.username = "ab cd"
    assert_not user.valid?
  end

  test "account name with @ is invalid" do
    user = users(:two)
    user.username = "ab@cd"
    assert_not user.valid?
  end

  test "account name over 30 characters is invalid" do
    user = users(:two)
    user.username = "a" * 31
    assert_not user.valid?
    assert_includes user.errors[:username], "is too long (maximum is 30 characters)"
  end

  test "account name must be unique case-insensitively" do
    users(:one).update!(username: "taken")
    user = users(:two)
    user.username = "TAKEN"
    assert_not user.valid?
    assert user.errors[:username].any?
  end

  test "two different users can both have no account name" do
    users(:one).update!(username: nil)
    users(:two).update!(username: nil)
    assert users(:one).valid?
    assert users(:two).valid?
  end

  test "human_attribute_name returns Account name for username" do
    assert_equal "Account name", User.human_attribute_name(:username)
  end

  # -- Reserved account names --

  test "reserved account names are rejected" do
    user = users(:two)
    User::RESERVED_USERNAMES.each do |name|
      user.username = name
      assert_not user.valid?, "Expected '#{name}' to be reserved but it was accepted"
      assert_includes user.errors[:username], "is reserved and cannot be used"
    end
  end

  test "reserved account name check is case-insensitive after normalisation" do
    user = users(:two)
    user.username = "Admin"
    assert_not user.valid?
    assert_includes user.errors[:username], "is reserved and cannot be used"
  end

  test "non-reserved account name is not affected by reserved check" do
    user = users(:two)
    user.username = "adminable"
    assert user.valid?, "Expected 'adminable' to be valid but got: #{user.errors.full_messages}"
  end
end
