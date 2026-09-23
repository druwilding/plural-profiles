require "test_helper"

class EmoteRegistryTest < ActiveSupport::TestCase
  def registry
    EmoteRegistry.current
  end

  def add_emote(name, group: emote_groups(:hearts))
    emote = Emote.new(emote_group: group, name: name)
    emote.image.attach(io: StringIO.new(png_bytes(8, 8)), filename: "#{name}.png", content_type: "image/png")
    emote.save!
    emote
  end

  test "entries are in group order, then natural name order" do
    add_emote("9_nine")
    add_emote("100_hundred")
    other = EmoteGroup.create!(name: "Other", position: 1, plain_text: "★")
    add_emote("01_first_other", group: other)

    names = registry.entries.map(&:name)
    assert_equal "01_dewdrop_heart", names.first
    assert_operator names.index("9_nine"), :<, names.index("100_hundred")
    assert_equal "01_first_other", names.last
  end

  test "resolves by name, code and alias" do
    emotes(:cadbury_heart).update!(name: "48_chocolate_heart")

    assert_equal "spring_heart", registry.resolve("02_spring_heart").code
    assert_equal "spring_heart", registry.resolve("spring_heart").code
    assert_equal "chocolate_heart", registry.resolve("cadbury_heart").code
  end

  test "resolves old Discord-numbered codes and aliases" do
    emotes(:cadbury_heart).update!(name: "48_chocolate_heart")

    assert_equal "aqua_heart", registry.resolve("11_aqua_heart").code
    assert_equal "chocolate_heart", registry.resolve("50cadbury_heart").code
  end

  test "a number is only stripped when a letter follows it" do
    add_emote("00")

    assert_nil registry.resolve("100")
    add_emote("100")
    assert_equal "100", registry.resolve("100").code
  end

  test "resolves ignoring case and hyphens" do
    assert_equal "aqua_heart", registry.resolve("Aqua-Heart").code
  end

  test "resolve returns nil for unknown or blank codes" do
    assert_nil registry.resolve("fake_heart")
    assert_nil registry.resolve("")
    assert_nil registry.resolve(nil)
  end

  test "archived emotes resolve but aren't pickable" do
    emotes(:red_heart).update!(archived_at: Time.current)

    assert registry.resolve("red_heart").archived?
    assert_includes registry.entries.map(&:code), "red_heart"
    assert_not_includes registry.pickable.map(&:code), "red_heart"
  end

  test "entries have a label and a display image path" do
    entry = registry.resolve("cadbury_heart")
    assert_equal "cadbury heart", entry.label
    assert_match %r{\A/rails/active_storage/representations/proxy/}, entry.src
  end

  test "a committed change is visible straight away in the same request" do
    assert_nil registry.resolve("party")
    add_emote("07_party")
    assert_equal "party", registry.resolve("party").code
  end

  test "is rebuilt when the database changes, even without a callback" do
    before = registry
    Emote.where(code: "red_heart").update_all(code: "rouge_heart", updated_at: 1.minute.from_now)
    EmoteRegistry.expire_current

    assert_not_equal before.version, registry.version
    assert_equal "rouge_heart", registry.resolve("36_red_heart").code
  end

  test "is reused while nothing changes" do
    before = registry
    EmoteRegistry.expire_current
    assert_same before, registry
  end
end
