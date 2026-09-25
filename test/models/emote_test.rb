require "test_helper"

class EmoteTest < ActiveSupport::TestCase
  def build_emote(name:, **attributes)
    emote = Emote.new(emote_group: emote_groups(:hearts), name: name, **attributes)
    emote.image.attach(io: StringIO.new(png_bytes(8, 8)), filename: "#{name}.png", content_type: "image/png")
    emote
  end

  test "name_from_filename" do
    assert_equal "02-spring-heart", Emote.name_from_filename("02 Spring-Heart.webp")
    assert_equal "02-spring-heart", Emote.name_from_filename("02_spring_heart.webp")
    assert_equal "100", Emote.name_from_filename("100.png")
    assert_equal "cadbury-heart", Emote.name_from_filename("__Cadbury__Heart__.svg")
    assert_equal "my-emote-v2", Emote.name_from_filename("my.emote v2.png")
    assert_equal "", Emote.name_from_filename("♥♥♥.png")
  end

  test "default_code drops the number prefix that sets the order" do
    assert_equal "spring-heart", Emote.default_code("02-spring-heart")
    assert_equal "cadbury-heart", Emote.default_code("50cadbury-heart")
    assert_equal "cadbury-heart", Emote.default_code("50-cadbury-heart")
    assert_equal "spring-heart", Emote.default_code("spring-heart")
    assert_equal "spring-heart", Emote.default_code("02_spring_heart")
  end

  test "default_code keeps numbers that are the emote itself" do
    assert_equal "100", Emote.default_code("100")
    assert_equal "1st-place", Emote.default_code("1st-place")
    assert_equal "2nd", Emote.default_code("2nd")
    assert_equal "3rd-place", Emote.default_code("3rd-place")
    assert_equal "4th-wall", Emote.default_code("4th-wall")
  end

  test "code is derived from the name" do
    emote = build_emote(name: "07-party")
    assert emote.save
    assert_equal "party", emote.code
  end

  test "renaming re-derives the code and keeps the old code as an alias" do
    emote = emotes(:cadbury_heart)
    emote.update!(name: "50-chocolate-heart")

    assert_equal "chocolate-heart", emote.code
    assert_equal [ "cadbury-heart" ], emote.aliases.pluck(:code)
  end

  test "renaming only the number prefix doesn't create an alias" do
    emote = emotes(:cadbury_heart)
    emote.update!(name: "50cadbury-heart")

    assert_equal "cadbury-heart", emote.code
    assert_empty emote.aliases
  end

  test "renaming back to an old code reclaims it from the aliases" do
    emote = emotes(:cadbury_heart)
    emote.update!(name: "48-chocolate-heart")
    emote.update!(name: "48-cadbury-heart")

    assert_equal "cadbury-heart", emote.code
    assert_equal [ "chocolate-heart" ], emote.aliases.pluck(:code)
  end

  test "an overridden code isn't re-derived on rename" do
    emote = emotes(:cadbury_heart)
    emote.update!(code: "cadbury", code_overridden: true)
    emote.update!(name: "99-cadbury-heart")

    assert_equal "cadbury", emote.code
  end

  test "names and codes are normalised to lowercase" do
    emote = build_emote(name: " 07-Party ")
    emote.valid?
    assert_equal "07-party", emote.name
  end

  test "underscores in names and codes become hyphens" do
    emote = build_emote(name: "07_big_party", code: "big_party", code_overridden: true)
    emote.valid?
    assert_equal "07-big-party", emote.name
    assert_equal "big-party", emote.code
  end

  test "codes can be looked up with underscores" do
    assert_equal emotes(:red_heart), Emote.find_by(code: "red_heart")
  end

  test "names must only contain lowercase letters, numbers and hyphens" do
    emote = build_emote(name: "party time!")
    assert_not emote.valid?
    assert_includes emote.errors[:name], "can only contain lowercase letters, numbers and hyphens"
  end

  test "requires an image" do
    emote = Emote.new(emote_group: emote_groups(:hearts), name: "07-party")
    assert_not emote.valid?
    assert emote.errors.added?(:image, :blank)
  end

  test "a code can't be used by another emote" do
    emote = build_emote(name: "99-red-heart")
    assert_not emote.valid?
    assert_includes emote.errors[:code], "“red-heart” is already used by 36-red-heart"
  end

  test "a name can't be another emote's code" do
    emote = build_emote(name: "red-heart", code: "other-red", code_overridden: true)
    assert_not emote.valid?
    assert_includes emote.errors[:name], "“red-heart” is already used by 36-red-heart"
  end

  test "a code can't be another emote's alias" do
    emotes(:cadbury_heart).update!(name: "48-chocolate-heart")

    emote = build_emote(name: "cadbury-heart")
    assert_not emote.valid?
    assert_includes emote.errors[:code], "“cadbury-heart” is an old code of 48-chocolate-heart"
  end

  test "an emote's name may equal its own code" do
    assert build_emote(name: "100").save
  end

  test "archive! and restore!" do
    emote = emotes(:red_heart)
    emote.archive!
    assert emote.archived?
    assert_includes Emote.archived, emote

    emote.restore!
    assert_not emote.archived?
    assert_includes Emote.active, emote
  end

  test "natural_sort orders numbers by value" do
    names = %w[10-b 2-a 1-c 100 9].map { |name| Emote.new(name: name) }
    assert_equal %w[1-c 2-a 9 10-b 100], Emote.natural_sort(names).map(&:name)
  end
end
