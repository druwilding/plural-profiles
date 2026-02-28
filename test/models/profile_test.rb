require "test_helper"

class ProfileTest < ActiveSupport::TestCase
  test "requires name" do
    profile = Profile.new(user: users(:one))
    assert_not profile.valid?
    assert_includes profile.errors[:name], "can't be blank"
  end

  test "generates uuid on create" do
    profile = users(:one).profiles.create!(name: "New Profile")
    assert_not_nil profile.uuid
    assert_match(/\A[0-9a-f-]{36}\z/, profile.uuid)
  end

  test "uuid must be unique" do
    existing = profiles(:alice)
    profile = Profile.new(user: users(:two), name: "Dupe", uuid: existing.uuid)
    assert_not profile.valid?
    assert_includes profile.errors[:uuid], "has already been taken"
  end

  test "to_param returns uuid" do
    profile = profiles(:alice)
    assert_equal profile.uuid, profile.to_param
  end

  test "belongs to user" do
    assert_equal users(:one), profiles(:alice).user
  end

  test "has many groups through group_profiles" do
    assert_includes profiles(:alice).groups, groups(:friends)
  end

  test "can attach avatar" do
    profile = profiles(:alice)
    profile.avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert profile.avatar.attached?
  end

  test "rejects non-image avatar" do
    profile = profiles(:alice)
    profile.avatar.attach(
      io: StringIO.new("<script>alert('xss')</script>"),
      filename: "evil.html",
      content_type: "text/html"
    )
    assert_not profile.valid?
    assert_includes profile.errors[:avatar], "must be a PNG, JPEG, GIF, or WebP image"
  end

  # Timestamp validations

  test "created_at in the past is valid" do
    profile = Profile.new(user: users(:one), name: "Test", created_at: 1.day.ago)
    profile.valid?
    assert_empty profile.errors[:created_at]
  end

  test "created_at in the future is invalid" do
    profile = Profile.new(user: users(:one), name: "Test", created_at: 2.minutes.from_now)
    assert_not profile.valid?
    assert_includes profile.errors[:created_at], "can't be in the future"
  end
end
