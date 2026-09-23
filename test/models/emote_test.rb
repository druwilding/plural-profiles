require "test_helper"

class EmoteTest < ActiveSupport::TestCase
  def build_emote(name:, **attributes)
    emote = Emote.new(emote_group: emote_groups(:hearts), name: name, **attributes)
    emote.image.attach(io: StringIO.new(png_bytes(8, 8)), filename: "#{name}.png", content_type: "image/png")
    emote
  end

  test "name_from_filename" do
    assert_equal "02_spring_heart", Emote.name_from_filename("02 Spring-Heart.webp")
    assert_equal "100", Emote.name_from_filename("100.png")
    assert_equal "cadbury_heart", Emote.name_from_filename("__Cadbury__Heart__.svg")
    assert_equal "my_emote_v2", Emote.name_from_filename("my.emote v2.png")
    assert_equal "", Emote.name_from_filename("♥♥♥.png")
  end

  test "default_code drops the number prefix that sets the order" do
    assert_equal "spring_heart", Emote.default_code("02_spring_heart")
    assert_equal "cadbury_heart", Emote.default_code("50cadbury_heart")
    assert_equal "cadbury_heart", Emote.default_code("50_cadbury_heart")
    assert_equal "spring_heart", Emote.default_code("spring_heart")
  end

  test "default_code keeps numbers that are the emote itself" do
    assert_equal "100", Emote.default_code("100")
    assert_equal "1st_place", Emote.default_code("1st_place")
    assert_equal "2nd", Emote.default_code("2nd")
    assert_equal "3rd_place", Emote.default_code("3rd_place")
    assert_equal "4th_wall", Emote.default_code("4th_wall")
  end

  test "code is derived from the name" do
    emote = build_emote(name: "07_party")
    assert emote.save
    assert_equal "party", emote.code
  end

  test "renaming re-derives the code and keeps the old code as an alias" do
    emote = emotes(:cadbury_heart)
    emote.update!(name: "50_chocolate_heart")

    assert_equal "chocolate_heart", emote.code
    assert_equal [ "cadbury_heart" ], emote.aliases.pluck(:code)
  end

  test "renaming only the number prefix doesn't create an alias" do
    emote = emotes(:cadbury_heart)
    emote.update!(name: "50cadbury_heart")

    assert_equal "cadbury_heart", emote.code
    assert_empty emote.aliases
  end

  test "renaming back to an old code reclaims it from the aliases" do
    emote = emotes(:cadbury_heart)
    emote.update!(name: "48_chocolate_heart")
    emote.update!(name: "48_cadbury_heart")

    assert_equal "cadbury_heart", emote.code
    assert_equal [ "chocolate_heart" ], emote.aliases.pluck(:code)
  end

  test "an overridden code isn't re-derived on rename" do
    emote = emotes(:cadbury_heart)
    emote.update!(code: "cadbury", code_overridden: true)
    emote.update!(name: "99_cadbury_heart")

    assert_equal "cadbury", emote.code
  end

  test "names and codes are normalised to lowercase" do
    emote = build_emote(name: " 07_Party ")
    emote.valid?
    assert_equal "07_party", emote.name
  end

  test "names must only contain lowercase letters, numbers and underscores" do
    emote = build_emote(name: "party time!")
    assert_not emote.valid?
    assert_includes emote.errors[:name], "can only contain lowercase letters, numbers and underscores"
  end

  test "requires an image" do
    emote = Emote.new(emote_group: emote_groups(:hearts), name: "07_party")
    assert_not emote.valid?
    assert emote.errors.added?(:image, :blank)
  end

  test "a code can't be used by another emote" do
    emote = build_emote(name: "99_red_heart")
    assert_not emote.valid?
    assert_includes emote.errors[:code], "“red_heart” is already used by 36_red_heart"
  end

  test "a name can't be another emote's code" do
    emote = build_emote(name: "red_heart", code: "other_red", code_overridden: true)
    assert_not emote.valid?
    assert_includes emote.errors[:name], "“red_heart” is already used by 36_red_heart"
  end

  test "a code can't be another emote's alias" do
    emotes(:cadbury_heart).update!(name: "48_chocolate_heart")

    emote = build_emote(name: "cadbury_heart")
    assert_not emote.valid?
    assert_includes emote.errors[:code], "“cadbury_heart” is an old code of 48_chocolate_heart"
  end

  test "an emote's name may equal its own code" do
    assert build_emote(name: "100").save
  end
end
