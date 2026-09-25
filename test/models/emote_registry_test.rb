require "test_helper"

class EmoteRegistryTest < ActiveSupport::TestCase
  def registry
    EmoteRegistry.current
  end

  def add_emote(name, emote_set: emote_sets(:hearts))
    emote = Emote.new(emote_set: emote_set, name: name)
    emote.image.attach(io: StringIO.new(png_bytes(8, 8)), filename: "#{name}.png", content_type: "image/png")
    emote.save!
    emote
  end

  test "entries are in set order, then natural name order" do
    add_emote("9-nine")
    add_emote("100-hundred")
    other = EmoteSet.create!(name: "Other", position: 1)
    add_emote("01-first-other", emote_set: other)

    names = registry.entries.map(&:name)
    assert_equal "01-dewdrop-heart", names.first
    assert_operator names.index("9-nine"), :<, names.index("100-hundred")
    assert_equal "01-first-other", names.last
  end

  test "resolves by name, code and alias" do
    emotes(:cadbury_heart).update!(name: "48-chocolate-heart")

    assert_equal "spring-heart", registry.resolve("02-spring-heart").code
    assert_equal "spring-heart", registry.resolve("spring-heart").code
    assert_equal "chocolate-heart", registry.resolve("cadbury-heart").code
  end

  test "resolves old Discord-numbered codes and aliases" do
    emotes(:cadbury_heart).update!(name: "48-chocolate-heart")

    assert_equal "aqua-heart", registry.resolve("11-aqua-heart").code
    assert_equal "chocolate-heart", registry.resolve("50cadbury-heart").code
  end

  test "a number is only stripped when a letter follows it" do
    add_emote("00")

    assert_nil registry.resolve("100")
    add_emote("100")
    assert_equal "100", registry.resolve("100").code
  end

  test "resolves ignoring case, and underscores for hyphens" do
    assert_equal "aqua-heart", registry.resolve("Aqua-Heart").code
    assert_equal "aqua-heart", registry.resolve("aqua_heart").code
    assert_equal "spring-heart", registry.resolve("02_spring_heart").code
  end

  test "resolves aliases written with underscores" do
    emotes(:cadbury_heart).update!(name: "48-chocolate-heart")

    assert_equal "chocolate-heart", registry.resolve("cadbury_heart").code
    assert_equal "chocolate-heart", registry.resolve("50_cadbury_heart").code
  end

  test "resolve returns nil for unknown or blank codes" do
    assert_nil registry.resolve("fake-heart")
    assert_nil registry.resolve("")
    assert_nil registry.resolve(nil)
  end

  test "archived emotes resolve but aren't pickable" do
    emotes(:red_heart).update!(archived_at: Time.current)

    assert registry.resolve("red-heart").archived?
    assert_includes registry.entries.map(&:code), "red-heart"
    assert_not_includes registry.pickable.map(&:code), "red-heart"
  end

  test "entries have a label and a display image path" do
    entry = registry.resolve("cadbury-heart")
    assert_equal "cadbury heart", entry.label
    assert_match %r{\A/rails/active_storage/representations/proxy/}, entry.src
  end

  test "a committed change is visible straight away in the same request" do
    assert_nil registry.resolve("party")
    add_emote("07-party")
    assert_equal "party", registry.resolve("party").code
  end

  test "is rebuilt when the database changes, even without a callback" do
    before = registry
    Emote.where(code: "red-heart").update_all(code: "rouge-heart", updated_at: 1.minute.from_now)
    EmoteRegistry.expire_current

    assert_not_equal before.version, registry.version
    assert_equal "rouge-heart", registry.resolve("36-red-heart").code
  end

  test "is reused while nothing changes" do
    before = registry
    EmoteRegistry.expire_current
    assert_same before, registry
  end

  # -- replace_codes --

  def replace(text)
    registry.replace_codes(text) { |emote| "[#{emote.code}]" }
  end

  test "replace_codes accepts every delimiter and separator combination" do
    [ ":cadbury-heart:", ";cadbury_heart;", ":cadbury-heart;", ";cadbury_heart:" ].each do |code|
      assert_equal "a [cadbury-heart] b", replace("a #{code} b"), "expected #{code} to be replaced"
    end
  end

  test "replace_codes accepts names, aliases and old numbered codes" do
    emotes(:cadbury_heart).update!(name: "48-chocolate-heart")

    assert_equal "[spring-heart] [chocolate-heart] [chocolate-heart] [aqua-heart]",
      replace(":02-spring-heart: :cadbury-heart: :50cadbury-heart: :11-aqua-heart:")
  end

  test "replace_codes replaces codes that don't end in _heart" do
    add_emote("100")
    assert_equal "that's [100]!", replace("that's :100:!")
  end

  test "replace_codes replaces codes side by side" do
    assert_equal "[red-heart][red-heart]", replace(":red-heart::red-heart:")
  end

  test "replace_codes leaves the closing delimiter of an unknown code to open the next one" do
    assert_equal "12:30[red-heart]", replace("12:30:red-heart:")
    assert_equal "ratio 3:2[red-heart]", replace("ratio 3:2:red-heart:")
    assert_equal ":nope[red-heart]", replace(":nope:red-heart:")
  end

  test "replace_codes leaves unknown codes and stray delimiters alone" do
    [ "a:b:c", ":unknown:", "10:30", "https://example.com", "::", ";)", "time: 12:30:45" ].each do |text|
      assert_equal text, replace(text)
    end
  end

  test "replace_codes only replaces a code that's exactly an emote" do
    assert_equal "10:100:", replace("10:100:")
    add_emote("100")
    assert_equal "10[100]", replace("10:100:")
  end

  test "replacing an emote's image changes the version and its image path, so every process picks it up" do
    before = registry
    old_src = before.resolve("red-heart").src

    emotes(:red_heart).image.attach(io: StringIO.new(png_bytes(8, 8)), filename: "new_red.png", content_type: "image/png")
    EmoteRegistry.expire_current

    assert_not_equal before.version, registry.version
    assert_not_equal old_src, registry.resolve("red-heart").src
    assert_match %r{/new_red\.png\z}, registry.resolve("red-heart").src
  end

  test "an old Discord number before a name resolves too" do
    emotes(:cadbury_heart).update!(code: "cadbury", code_overridden: true, name: "cadbury-heart")

    assert_equal "cadbury", registry.resolve("50cadbury-heart").code
  end

  # Every way heart codes were written before emotes moved into the database
  # (and before identifiers switched to hyphens), so existing profiles and
  # messages keep rendering.
  test "resolves every form old heart codes were written in" do
    {
      "aqua-heart" => %w[aqua_heart AQUA_HEART Aqua_Heart 11_AQUA_HEART aqua-heart 11-aqua-heart 11_aqua_heart],
      "cadbury-heart" => %w[cadbury_heart 50cadbury_heart 51cadbury_heart 50_cadbury_heart],
      "red-heart" => %w[36_red_heart 999_red_heart],
      "dewdrop-heart" => %w[01_dewdrop_heart]
    }.each do |code, typed_forms|
      typed_forms.each { |typed| assert_equal code, registry.resolve(typed)&.code, "expected #{typed} to resolve to #{code}" }
    end
    assert_nil registry.resolve("99_fake_heart")
  end
end
