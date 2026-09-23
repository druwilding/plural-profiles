require "test_helper"

class HeartEmojiTest < ActiveSupport::TestCase
  test "all lists every pickable emote's code in display order" do
    assert_equal "dewdrop_heart", HeartEmoji.all.first
    assert_equal "sunshine_heart", HeartEmoji.all.last
    assert_includes HeartEmoji.all, "red_heart"
    assert_equal HeartEmoji.all.uniq, HeartEmoji.all
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

  test "image_path points at the emote's display image" do
    assert_equal EmoteRegistry.current.resolve("abyss_heart").src, HeartEmoji.image_path("abyss_heart")
    assert_match %r{\A/rails/active_storage/representations/proxy/.+/13_abyss_heart\.webp\z}, HeartEmoji.image_path("abyss_heart")
  end

  test "image_path is nil for an unknown heart" do
    assert_nil HeartEmoji.image_path("fake_heart")
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
