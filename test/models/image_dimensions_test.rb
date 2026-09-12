require "test_helper"

class ImageDimensionsTest < ActiveSupport::TestCase
  test "returns width and height for a pending attachment" do
    # An unsaved record, so attach() leaves the attachment pending instead of
    # auto-saving (and uploading) it immediately.
    profile = Profile.new(user: users(:one), name: "Pending Avatar Test")
    profile.avatar.attach(
      io: StringIO.new(png_bytes(120, 80)),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert_equal [ 120, 80 ], ImageDimensions.for(profile.avatar)
  end

  test "returns nil when nothing is attached" do
    profile = profiles(:alice)
    assert_nil ImageDimensions.for(profile.avatar)
  end

  test "returns nil for an attachment that isn't changing" do
    profile = profiles(:alice)
    profile.avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert profile.save

    profile.reload
    assert profile.avatar.attached?
    assert_nil ImageDimensions.for(profile.avatar)
  end

  test "returns nil for a pending attachment over the decodable size" do
    profile = profiles(:alice)
    profile.avatar.attach(
      io: StringIO.new("a" * (ImageDimensions::MAX_DECODABLE_SIZE + 1)),
      filename: "toobig.png",
      content_type: "image/png"
    )
    assert_nil ImageDimensions.for(profile.avatar)
  end

  test "returns nil instead of raising for unreadable image data" do
    profile = profiles(:alice)
    profile.avatar.attach(
      io: StringIO.new("not actually an image"),
      filename: "fake.png",
      content_type: "image/png"
    )
    assert_nil ImageDimensions.for(profile.avatar)
  end

  test "does not consume the pending io, so the real upload still succeeds" do
    profile = profiles(:alice)
    io = StringIO.new(png_bytes(50, 50))
    profile.avatar.attach(io: io, filename: "avatar.png", content_type: "image/png")

    ImageDimensions.for(profile.avatar)

    assert profile.save
    assert profile.avatar.attached?
    assert_equal 50, Vips::Image.new_from_buffer(profile.avatar.download, "").width
  end
end
