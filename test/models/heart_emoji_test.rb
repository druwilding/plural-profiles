require "test_helper"

class HeartEmojiTest < ActiveSupport::TestCase
  test "ALL contains expected hearts" do
    assert_includes HeartEmoji::ALL, "dewdrop_heart"
    assert_includes HeartEmoji::ALL, "red_heart"
  end

  test "ALL has no duplicates and is well-formed" do
    assert_equal HeartEmoji::ALL.uniq, HeartEmoji::ALL
    assert HeartEmoji::ALL.all? { |heart| heart.match?(/\A[a-z]+_heart\z/) },
      "expected every entry to be a lowercase name ending in _heart"
  end

  test "every heart has an image" do
    HeartEmoji::ALL.each do |heart|
      assert File.exist?(Rails.public_path.join("images/hearts/#{heart}.webp")), "missing image for #{heart}"
    end
  end

  test "resolve is case-insensitive" do
    assert_equal "aqua_heart", HeartEmoji.resolve("11_AQUA_HEART")
    assert_equal "aqua_heart", HeartEmoji.resolve("AQUA_HEART")
    assert_equal "aqua_heart", HeartEmoji.resolve("Aqua_Heart")
  end

  test "resolve returns canonical name for bare name" do
    assert_equal "aqua_heart", HeartEmoji.resolve("aqua_heart")
    assert_equal "cadbury_heart", HeartEmoji.resolve("cadbury_heart")
  end

  test "resolve accepts hyphens in place of underscores" do
    assert_equal "aqua_heart", HeartEmoji.resolve("aqua-heart")
    assert_equal "aqua_heart", HeartEmoji.resolve("11-aqua-heart")
  end

  test "resolve strips a number prefix regardless of what number it is" do
    assert_equal "aqua_heart", HeartEmoji.resolve("11_aqua_heart")
    assert_equal "cadbury_heart", HeartEmoji.resolve("50cadbury_heart")
    assert_equal "dewdrop_heart", HeartEmoji.resolve("01_dewdrop_heart")
    assert_equal "red_heart", HeartEmoji.resolve("36_red_heart")
    assert_equal "red_heart", HeartEmoji.resolve("999_red_heart")
  end

  test "resolve handles cadbury's no-underscore number prefix in every form" do
    assert_equal "cadbury_heart", HeartEmoji.resolve("cadbury_heart")
    assert_equal "cadbury_heart", HeartEmoji.resolve("50cadbury_heart")
    assert_equal "cadbury_heart", HeartEmoji.resolve("51cadbury_heart")
    assert_equal "cadbury_heart", HeartEmoji.resolve("50_cadbury_heart")
  end

  test "resolve returns nil for unknown name" do
    assert_nil HeartEmoji.resolve("fake_heart")
    assert_nil HeartEmoji.resolve("99_fake_heart")
  end

  test "display_name formats name" do
    assert_equal "dewdrop heart", HeartEmoji.display_name("dewdrop_heart")
    assert_equal "cadbury heart", HeartEmoji.display_name("cadbury_heart")
  end

  test "image_path points at the public heart image" do
    assert_equal "/images/hearts/abyss_heart.webp", HeartEmoji.image_path("abyss_heart")
  end

  test "code is the canonical colon form" do
    assert_equal ":abyss_heart:", HeartEmoji.code("abyss_heart")
  end

  test "PATTERN matches every delimiter and separator combination" do
    [ ":cadbury_heart:", ";cadbury-heart;", ":cadbury_heart;", ";cadbury_heart:" ].each do |code|
      assert_match HeartEmoji::PATTERN, code
      assert_equal "cadbury", code.match(HeartEmoji::PATTERN)[1][0, 7]
    end
  end
end
