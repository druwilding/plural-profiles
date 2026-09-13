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

  test "accepts avatar at exactly 4000x4000 pixels" do
    profile = profiles(:alice)
    profile.avatar.attach(
      io: StringIO.new(png_bytes(4000, 4000)),
      filename: "big.png",
      content_type: "image/png"
    )
    assert profile.valid?
  end

  test "rejects avatar over 4000x4000 pixels" do
    profile = profiles(:alice)
    profile.avatar.attach(
      io: StringIO.new(png_bytes(4001, 100)),
      filename: "toohuge.png",
      content_type: "image/png"
    )
    assert_not profile.valid?
    assert_includes profile.errors[:avatar], "must be 4000×4000 pixels or smaller"
  end

  test "does not re-check dimensions of an avatar that isn't changing" do
    profile = profiles(:alice)
    profile.avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert profile.save

    profile.reload
    assert_nil ImageDimensions.for(profile.avatar)

    profile.name = "Alice updated"
    assert profile.valid?
  end

  # Timestamp validations

  test "created_at in the past is valid" do
    profile = Profile.new(user: users(:one), name: "Test", created_at: 1.day.ago)
    profile.valid?
    assert_empty profile.errors[:created_at]
  end

  test "created_at in the future is valid" do
    profile = Profile.new(user: users(:one), name: "Test", created_at: 2.minutes.from_now)
    profile.valid?
    assert_empty profile.errors[:created_at]
  end

  # Heart emojis

  test "heart_emojis defaults to empty array" do
    profile = users(:one).profiles.create!(name: "Heartless")
    assert_equal [], profile.heart_emojis
  end

  test "valid heart emojis are accepted" do
    profile = profiles(:alice)
    profile.heart_emojis = %w[dewdrop_heart red_heart]
    assert profile.valid?
  end

  test "invalid heart emoji names are rejected" do
    profile = profiles(:alice)
    profile.heart_emojis = %w[dewdrop_heart fake_heart]
    assert_not profile.valid?
    assert profile.errors[:heart_emojis].any? { |e| e.include?("fake_heart") }
  end

  test "assigning heart_emojis normalizes old number prefixes to their bare form" do
    profile = profiles(:alice)
    profile.heart_emojis = %w[13_storm_heart 50cadbury_heart]
    assert_equal %w[storm_heart cadbury_heart], profile.heart_emojis
    assert profile.valid?
  end

  test "assigning heart_emojis leaves genuinely unknown hearts untouched so they still fail validation" do
    profile = profiles(:alice)
    profile.heart_emojis = %w[dewdrop_heart 99_fake_heart]
    assert_equal %w[dewdrop_heart 99_fake_heart], profile.heart_emojis
    assert_not profile.valid?
    assert profile.errors[:heart_emojis].any? { |e| e.include?("99_fake_heart") }
  end

  test "assigning heart_emojis normalizes uppercase and mixed case" do
    profile = profiles(:alice)
    profile.heart_emojis = %w[11_AQUA_HEART Red_Heart]
    assert_equal %w[aqua_heart red_heart], profile.heart_emojis
    assert profile.valid?
  end

  # -- chat identity (mini-profile) --

  test "chat fields default to inheriting the main field" do
    profile = profiles(:alice)
    assert_equal profile.name, profile.chat_name
    assert_equal profile.pronouns, profile.chat_pronouns
    assert_equal profile.tag_line, profile.chat_tag_line
    assert_equal profile.heart_emojis, profile.chat_heart_emojis
  end

  # Description is the one exception: it defaults to NOT inherited (and
  # blank), unlike every other field — it's the field people are most
  # likely to want to keep out of chat entirely, or write a shorter version
  # of, so it doesn't default to silently mirroring whatever the full
  # profile's (possibly long, possibly not chat-appropriate) description says.
  test "chat_description defaults to not inherited and blank, unlike every other field" do
    profile = profiles(:alice)
    assert profile.description.present?
    assert_not profile.mini_profile_description_inherited?
    assert_nil profile.chat_description
  end

  test "chat_subtitle inherits even when the main subtitle is blank" do
    profile = profiles(:alice)
    assert_nil profile.subtitle
    assert_nil profile.chat_subtitle
  end

  test "inherited chat fields track live changes to the main field" do
    profile = profiles(:alice)
    profile.update!(tag_line: "New tagline")
    assert_equal "New tagline", profile.chat_tag_line
  end

  test "setting a field to not inherited uses the independent mini_profile value instead" do
    profile = profiles(:alice)
    profile.update!(mini_profile_pronouns_inherited: false, mini_profile_pronouns: "it/its")
    assert_equal "it/its", profile.chat_pronouns
    assert_not_equal profile.pronouns, profile.chat_pronouns
  end

  test "a not-inherited field left blank resolves to blank, not the main value" do
    profile = profiles(:alice)
    profile.update!(mini_profile_subtitle_inherited: false, mini_profile_subtitle: nil)
    assert_nil profile.chat_subtitle
  end

  test "mini_profile_name_inherited defaults to true and every other chat field defaults to true, except description" do
    profile = users(:one).profiles.create!(name: "Fresh")
    assert profile.mini_profile_name_inherited?
    assert profile.mini_profile_subtitle_inherited?
    assert profile.mini_profile_tag_line_inherited?
    assert profile.mini_profile_pronouns_inherited?
    assert profile.mini_profile_heart_emojis_inherited?
    assert profile.mini_profile_avatar_inherited?
    assert_not profile.mini_profile_description_inherited?
  end

  test "mini_profile_link_enabled defaults to false" do
    profile = users(:one).profiles.create!(name: "Fresh")
    assert_not profile.mini_profile_link_enabled?
  end

  test "mini_profile_name can be blank while inherited" do
    profile = profiles(:alice)
    assert_nil profile.mini_profile_name
    assert profile.valid?
  end

  test "mini_profile_name must be present once name is set to not inherited" do
    profile = profiles(:alice)
    profile.mini_profile_name_inherited = false
    profile.mini_profile_name = nil
    assert_not profile.valid?
    assert_includes profile.errors[:mini_profile_name], "can't be blank when not inheriting the main name"
  end

  test "chat_name uses the independent name once set" do
    profile = profiles(:alice)
    profile.update!(mini_profile_name_inherited: false, mini_profile_name: "Nickname")
    assert_equal "Nickname", profile.chat_name
  end

  test "valid mini_profile_heart_emojis are accepted" do
    profile = profiles(:alice)
    profile.mini_profile_heart_emojis = %w[dewdrop_heart red_heart]
    assert profile.valid?
  end

  test "invalid mini_profile_heart_emojis are rejected" do
    profile = profiles(:alice)
    profile.mini_profile_heart_emojis = %w[dewdrop_heart fake_heart]
    assert_not profile.valid?
    assert profile.errors[:mini_profile_heart_emojis].any? { |e| e.include?("fake_heart") }
  end

  test "assigning mini_profile_heart_emojis normalizes old number prefixes to their bare form" do
    profile = profiles(:alice)
    profile.mini_profile_heart_emojis = %w[13_storm_heart 50cadbury_heart]
    assert_equal %w[storm_heart cadbury_heart], profile.mini_profile_heart_emojis
    assert profile.valid?
  end

  test "can attach a mini_profile_avatar independently of the main avatar" do
    profile = profiles(:alice)
    profile.mini_profile_avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert profile.mini_profile_avatar.attached?
    assert_not profile.avatar.attached?
  end

  test "rejects non-image mini_profile_avatar" do
    profile = profiles(:alice)
    profile.mini_profile_avatar.attach(
      io: StringIO.new("<script>alert('xss')</script>"),
      filename: "evil.html",
      content_type: "text/html"
    )
    assert_not profile.valid?
    assert_includes profile.errors[:mini_profile_avatar], "must be a JPG/JPEG, PNG, or WebP image"
  end

  test "rejects mini_profile_avatar over 2 MB" do
    profile = profiles(:alice)
    profile.mini_profile_avatar.attach(
      io: StringIO.new("a" * (HasAvatar::AVATAR_MAX_SIZE + 1)),
      filename: "toobig.png",
      content_type: "image/png"
    )
    assert_not profile.valid?
    assert_includes profile.errors[:mini_profile_avatar], "must be 2 MB or less"
  end

  test "rejects mini_profile_avatar over 4000x4000 pixels" do
    profile = profiles(:alice)
    profile.mini_profile_avatar.attach(
      io: StringIO.new(png_bytes(4001, 4001)),
      filename: "toohuge.png",
      content_type: "image/png"
    )
    assert_not profile.valid?
    assert_includes profile.errors[:mini_profile_avatar], "must be 4000×4000 pixels or smaller"
  end

  test "mini_profile_avatar_shape defaults to rounded" do
    profile = users(:one).profiles.create!(name: "Fresh")
    assert_equal "rounded", profile.mini_profile_avatar_shape
  end

  test "mini_profile_avatar_shape is independent of avatar_shape" do
    profile = profiles(:alice)
    profile.update!(avatar_shape: "square", mini_profile_avatar_shape: "circle")
    assert_equal "square", profile.avatar_shape
    assert_equal "circle", profile.mini_profile_avatar_shape
  end

  test "rejects an invalid mini_profile_avatar_shape" do
    profile = profiles(:alice)
    profile.mini_profile_avatar_shape = "triangle"
    assert_not profile.valid?
    assert_includes profile.errors[:mini_profile_avatar_shape], "is not included in the list"
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

  test "name_and_label_sort_key uses downcased name so mixed-case sorts correctly" do
    profile = profiles(:alice)
    profile.name = "Zebra"
    assert_equal "zebra", profile.name_and_label_sort_key.first
  end

  test "name_and_label_sort_key sorts unlabelled before labelled" do
    profile = profiles(:alice)
    profile.labels = []
    unlabelled_key = profile.name_and_label_sort_key

    profile.labels = [ "work" ]
    labelled_key = profile.name_and_label_sort_key

    assert (unlabelled_key <=> labelled_key) < 0
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

  # -- Chat proxy brackets (Phase 3) --

  test "chat brackets are optional" do
    profile = users(:one).profiles.build(name: "No Brackets")
    assert profile.valid?
  end

  test "chat brackets accept a before-only template" do
    profile = users(:one).profiles.build(name: "Guy", chat_bracket_before: "guy:")
    assert profile.valid?
  end

  test "chat brackets accept an after-only template" do
    profile = users(:one).profiles.build(name: "Suffix", chat_bracket_after: "-g")
    assert profile.valid?
  end

  test "chat brackets accept both a before and an after" do
    profile = users(:one).profiles.build(name: "Brace", chat_bracket_before: "{", chat_bracket_after: "}")
    assert profile.valid?
  end

  test "chat brackets normalize blank input to nil" do
    profile = users(:one).profiles.build(name: "Blank", chat_bracket_before: "   ", chat_bracket_after: "   ")
    profile.valid?
    assert_nil profile.chat_bracket_before
    assert_nil profile.chat_bracket_after
  end

  test "chat brackets strip surrounding whitespace" do
    profile = users(:one).profiles.build(name: "Spacey", chat_bracket_before: "  guy:  ", chat_bracket_after: "  !  ")
    profile.valid?
    assert_equal "guy:", profile.chat_bracket_before
    assert_equal "!", profile.chat_bracket_after
  end

  test "chat brackets must be an exact unique before/after combination per user" do
    users(:one).profiles.create!(name: "First", chat_bracket_before: "guy:")
    dupe = users(:one).profiles.build(name: "Second", chat_bracket_before: "guy:")
    assert_not dupe.valid?
    assert_includes dupe.errors[:base], "The chat proxy brackets are already used by another profile or group"
  end

  test "chat brackets in a different case are treated as distinct, not duplicates" do
    users(:one).profiles.create!(name: "First", chat_bracket_before: "guy:")
    other = users(:one).profiles.build(name: "Second", chat_bracket_before: "GUY:")
    assert other.valid?
  end

  test "chat brackets allow the same before with a different after" do
    users(:one).profiles.create!(name: "First", chat_bracket_before: "guy:")
    other = users(:one).profiles.build(name: "Second", chat_bracket_before: "guy:", chat_bracket_after: "!")
    assert other.valid?
  end

  test "chat brackets can repeat across different users" do
    users(:one).profiles.create!(name: "Mine", chat_bracket_before: "guy:")
    other = users(:two).profiles.build(name: "Theirs", chat_bracket_before: "guy:")
    assert other.valid?
  end

  test "chat brackets collide with a group's brackets for the same user" do
    users(:one).groups.create!(name: "Existing Group", chat_bracket_before: "guy:")
    dupe = users(:one).profiles.build(name: "Second", chat_bracket_before: "guy:")
    assert_not dupe.valid?
    assert_includes dupe.errors[:base], "The chat proxy brackets are already used by another profile or group"
  end
end
