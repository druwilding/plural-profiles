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
    assert_includes profile.errors[:avatar], "must be a JPG/JPEG, PNG, or WebP image"
  end

  test "rejects avatar over 2 MB" do
    profile = profiles(:alice)
    profile.avatar.attach(
      io: StringIO.new("a" * (HasAvatar::AVATAR_MAX_SIZE + 1)),
      filename: "toobig.png",
      content_type: "image/png"
    )
    assert_not profile.valid?
    assert_includes profile.errors[:avatar], "must be 2 MB or less"
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

  # Heart emojis

  test "heart_emojis defaults to empty array" do
    profile = users(:one).profiles.create!(name: "Heartless")
    assert_equal [], profile.heart_emojis
  end

  test "valid heart emojis are accepted" do
    profile = profiles(:alice)
    profile.heart_emojis = %w[01_dewdrop_heart 36_red_heart]
    assert profile.valid?
  end

  test "invalid heart emoji names are rejected" do
    profile = profiles(:alice)
    profile.heart_emojis = %w[01_dewdrop_heart fake_heart]
    assert_not profile.valid?
    assert profile.errors[:heart_emojis].any? { |e| e.include?("fake_heart") }
  end

  test "heart_emoji_display_name formats name" do
    profile = profiles(:alice)
    assert_equal "dewdrop heart", profile.heart_emoji_display_name("01_dewdrop_heart")
    assert_equal "cadbury heart", profile.heart_emoji_display_name("50cadbury_heart")
  end

  test "HEART_EMOJIS constant contains expected hearts" do
    assert_includes Profile::HEART_EMOJIS, "01_dewdrop_heart"
    assert_includes Profile::HEART_EMOJIS, "36_red_heart"
    assert_equal 42, Profile::HEART_EMOJIS.size
  end

  test "resolve_heart_emoji returns canonical name for full name" do
    assert_equal "11_aqua_heart", Profile.resolve_heart_emoji("11_aqua_heart")
    assert_equal "50cadbury_heart", Profile.resolve_heart_emoji("50cadbury_heart")
  end

  test "resolve_heart_emoji returns canonical name for short alias" do
    assert_equal "11_aqua_heart", Profile.resolve_heart_emoji("aqua_heart")
    assert_equal "50cadbury_heart", Profile.resolve_heart_emoji("cadbury_heart")
    assert_equal "01_dewdrop_heart", Profile.resolve_heart_emoji("dewdrop_heart")
    assert_equal "36_red_heart", Profile.resolve_heart_emoji("red_heart")
  end

  test "resolve_heart_emoji returns nil for unknown name" do
    assert_nil Profile.resolve_heart_emoji("fake_heart")
    assert_nil Profile.resolve_heart_emoji("99_fake_heart")
  end

  test "HEART_EMOJI_ALIASES maps every short name to its canonical entry" do
    assert_equal "11_aqua_heart", Profile::HEART_EMOJI_ALIASES["aqua_heart"]
    assert_equal "50cadbury_heart", Profile::HEART_EMOJI_ALIASES["cadbury_heart"]
    assert_equal 42, Profile::HEART_EMOJI_ALIASES.size
  end

  # -- labels --

  test "labels defaults to empty array" do
    profile = users(:one).profiles.create!(name: "Labels Test")
    assert_equal [], profile.labels
  end

  test "labels_text= parses comma-separated string into array" do
    profile = profiles(:alice)
    profile.labels_text = "safe, work, close friends"
    assert_equal [ "safe", "work", "close friends" ], profile.labels
  end

  test "labels_text= trims whitespace and rejects blanks" do
    profile = profiles(:alice)
    profile.labels_text = "  safe ,, work ,  "
    assert_equal [ "safe", "work" ], profile.labels
  end

  test "labels_text= deduplicates entries" do
    profile = profiles(:alice)
    profile.labels_text = "safe, safe, work"
    assert_equal [ "safe", "work" ], profile.labels
  end

  test "labels_text returns labels joined with comma and space" do
    profile = profiles(:alice)
    profile.labels = [ "safe", "work" ]
    assert_equal "safe, work", profile.labels_text
  end

  test "labels_text returns empty string when no labels" do
    profile = profiles(:alice)
    profile.labels = []
    assert_equal "", profile.labels_text
  end

  test "normalize_labels cleans up array on validation" do
    profile = profiles(:alice)
    profile.labels = [ "  safe  ", "", "work" ]
    profile.validate
    assert_equal [ "safe", "work" ], profile.labels
  end

  test "labels round-trip through save" do
    profile = users(:one).profiles.create!(name: "Labels RT")
    profile.update!(labels: [ "family", "private" ])
    assert_equal [ "family", "private" ], profile.reload.labels
  end

  # -- Profile theme association --

  test "profile without a theme is valid" do
    profile = users(:one).profiles.build(name: "Themeless")
    assert profile.valid?
  end

  test "profile with a theme is valid" do
    profile = users(:one).profiles.build(name: "Themed", theme: themes(:dark_forest))
    assert profile.valid?
  end

  test "theme association is accessible via fixture" do
    assert_equal themes(:dark_forest), profiles(:alice).theme
  end

  test "deleting a theme nullifies the profile theme_id" do
    profile = users(:one).profiles.create!(name: "Will Lose Theme", theme: themes(:sunset))
    assert_not_nil profile.theme_id
    themes(:sunset).destroy
    assert_nil profile.reload.theme_id
  end

  # -- Copy lineage (Phase 5) --

  test "copied_from association" do
    original = users(:one).profiles.create!(name: "Original")
    copy = users(:one).profiles.create!(name: "Copy", copied_from: original)
    assert_equal original, copy.copied_from
  end

  test "copies association" do
    original = users(:one).profiles.create!(name: "Original")
    copy1 = users(:one).profiles.create!(name: "Copy 1", copied_from: original)
    copy2 = users(:one).profiles.create!(name: "Copy 2", copied_from: original)
    assert_includes original.copies, copy1
    assert_includes original.copies, copy2
  end

  test "copies_with_labels returns copies that have ALL given labels" do
    original = users(:one).profiles.create!(name: "Original")
    matching = users(:one).profiles.create!(name: "Matching", copied_from: original, labels: [ "blue", "safe" ])
    partial  = users(:one).profiles.create!(name: "Partial",  copied_from: original, labels: [ "blue" ])
    other    = users(:one).profiles.create!(name: "Other",    copied_from: original, labels: [ "red" ])

    result = original.copies_with_labels([ "blue", "safe" ])
    assert_includes result, matching
    assert_not_includes result, partial
    assert_not_includes result, other
  end

  test "copies_with_labels returns empty when no copies match" do
    original = users(:one).profiles.create!(name: "Original")
    users(:one).profiles.create!(name: "Copy", copied_from: original, labels: [ "red" ])
    assert_empty original.copies_with_labels([ "blue" ])
  end

  test "copies_with_labels finds transitive copies (copy of a copy)" do
    original = users(:one).profiles.create!(name: "Original")
    copy_purple = users(:one).profiles.create!(name: "Copy (purple)", copied_from: original, labels: [ "purple" ])
    copy_yellow = users(:one).profiles.create!(name: "Copy (yellow)", copied_from: copy_purple, labels: [ "yellow" ])

    result = original.copies_with_labels([ "yellow" ])
    assert_includes result, copy_yellow
    assert_not_includes result, copy_purple
  end

  test "copies_with_labels finds deeply nested transitive copies" do
    original = users(:one).profiles.create!(name: "Original")
    gen1 = users(:one).profiles.create!(name: "Gen 1", copied_from: original, labels: [ "a" ])
    gen2 = users(:one).profiles.create!(name: "Gen 2", copied_from: gen1, labels: [ "b" ])
    gen3 = users(:one).profiles.create!(name: "Gen 3", copied_from: gen2, labels: [ "c" ])

    result = original.copies_with_labels([ "c" ])
    assert_includes result, gen3
    assert_equal 1, result.count
  end

  test "deleting the original nullifies copied_from_id on copies" do
    original = users(:one).profiles.create!(name: "Original")
    copy = users(:one).profiles.create!(name: "Copy", copied_from: original)
    original.destroy
    assert_nil copy.reload.copied_from_id
  end
end
