require "test_helper"

class ThemeTest < ActiveSupport::TestCase
  test "requires name" do
    theme = Theme.new(user: users(:one), colors: { "page_bg" => "#000000" })
    assert_not theme.valid?
    assert_includes theme.errors[:name], "can't be blank"
  end

  test "requires colors" do
    theme = Theme.new(user: users(:one), name: "Test")
    theme.colors = nil
    assert_not theme.valid?
    assert_includes theme.errors[:colors], "must be a hash"
  end

  test "belongs to user" do
    assert_equal users(:one), themes(:dark_forest).user
  end

  test "accepts background image within size, type, and dimension limits" do
    theme = themes(:dark_forest)
    theme.background_image.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "background.png",
      content_type: "image/png"
    )
    assert theme.valid?
  end

  test "rejects non-image background image" do
    theme = themes(:dark_forest)
    theme.background_image.attach(
      io: StringIO.new("<script>alert('xss')</script>"),
      filename: "evil.html",
      content_type: "text/html"
    )
    assert_not theme.valid?
    assert_includes theme.errors[:background_image], "must be a JPG/JPEG, PNG, or WebP image"
  end

  test "rejects background image over 2 MB" do
    theme = themes(:dark_forest)
    theme.background_image.attach(
      io: StringIO.new("a" * (Theme::BACKGROUND_IMAGE_MAX_SIZE + 1)),
      filename: "toobig.png",
      content_type: "image/png"
    )
    assert_not theme.valid?
    assert_includes theme.errors[:background_image], "must be 2 MB or less"
  end

  test "accepts background image at exactly 4000x4000 pixels" do
    theme = themes(:dark_forest)
    theme.background_image.attach(
      io: StringIO.new(png_bytes(4000, 4000)),
      filename: "big.png",
      content_type: "image/png"
    )
    assert theme.valid?
  end

  test "rejects background image over 4000x4000 pixels" do
    theme = themes(:dark_forest)
    theme.background_image.attach(
      io: StringIO.new(png_bytes(100, 4001)),
      filename: "toohuge.png",
      content_type: "image/png"
    )
    assert_not theme.valid?
    assert_includes theme.errors[:background_image], "must be 4000×4000 pixels or smaller"
  end

  test "color_for returns stored colour" do
    theme = themes(:dark_forest)
    assert_equal "#0e2e24", theme.color_for("page_bg")
  end

  test "color_for falls back to default" do
    theme = Theme.new(user: users(:one), name: "Empty", colors: {})
    assert_equal "#0b221b", theme.color_for("page_bg")
  end

  test "swatch_colors returns five colours in SWATCH_PROPERTIES order" do
    theme = themes(:dark_forest)
    swatches = theme.swatch_colors
    assert_equal Theme::SWATCH_PROPERTIES.length, swatches.length
    Theme::SWATCH_PROPERTIES.each_with_index do |prop, i|
      assert_equal theme.color_for(prop), swatches[i]
    end
  end

  test "swatch_colors falls back to defaults when colours are absent" do
    theme = Theme.new(user: users(:one), name: "Empty", colors: {})
    expected = Theme::SWATCH_PROPERTIES.map { |prop| Theme::THEMEABLE_PROPERTIES.dig(prop, :default) }
    assert_equal expected, theme.swatch_colors
  end

  test "to_css_properties generates inline style string" do
    theme = themes(:dark_forest)
    css = theme.to_css_properties
    assert_includes css, "--page-bg: #0e2e24;"
    assert_includes css, "--pane-bg: #133b2f;"
    assert_includes css, "--pane-link: #3ab580;"
  end

  test "to_css_properties includes derived tree-guide and avatar-placeholder-border using theme text color" do
    # Use a text colour that differs from the default (#5ea389) so the test fails
    # if to_css_properties accidentally falls back to the default instead of the
    # theme's overridden value.  Expected percentages come from the single source
    # of truth (DERIVED_TEXT_PROPERTIES) so the test stays in sync automatically.
    # Setting pane_text alone also drives the --chat-* twins, since chat_pane_text
    # inherits from pane_text until someone overrides it.
    theme = Theme.new(user: users(:one), name: "Custom text", colors: { "pane_text" => "#abcdef" })
    css = theme.to_css_properties
    Theme::DERIVED_TEXT_PROPERTIES.each do |css_prop, meta|
      assert_includes css, "--#{css_prop}: color-mix(in srgb, #abcdef #{meta[:percent]}%, transparent);"
    end
  end

  test "derived chat properties follow chat_pane_text once it is overridden" do
    theme = Theme.new(user: users(:one), name: "Split text",
                      colors: { "pane_text" => "#abcdef", "chat_pane_text" => "#fedcba" })
    css = theme.to_css_properties

    Theme::DERIVED_TEXT_PROPERTIES.each do |css_prop, meta|
      expected = meta[:source] == "chat_pane_text" ? "#fedcba" : "#abcdef"
      assert_includes css, "--#{css_prop}: color-mix(in srgb, #{expected} #{meta[:percent]}%, transparent);"
    end
  end

  test "to_css generates a full root block" do
    theme = themes(:dark_forest)
    css = theme.to_css
    assert css.start_with?(":root {")
    assert css.end_with?("}")
    assert_includes css, "  --page-bg: #0e2e24;"
  end

  test "THEMEABLE_PROPERTIES covers all expected groups" do
    groups = Theme::THEMEABLE_PROPERTIES.values.map { |v| v[:group] }.uniq
    assert_includes groups, :page
    assert_includes groups, :header
    assert_includes groups, :pane
    assert_includes groups, :forms
    assert_includes groups, :buttons
    assert_includes groups, :flash
  end

  # ── Chat colour inheritance ─────────────────────────────────────────────

  test "color_for returns the stored value when the chat key is set" do
    theme = Theme.new(user: users(:one), name: "Set",
                      colors: { "pane_bg" => "#111111", "chat_pane_bg" => "#222222" })
    assert_equal "#222222", theme.color_for("chat_pane_bg")
  end

  test "color_for inherits the parent's stored value, not the parent's default" do
    theme = Theme.new(user: users(:one), name: "Inherited", colors: { "pane_bg" => "#111111" })
    assert_equal "#111111", theme.color_for("chat_pane_bg")
    refute_equal Theme::THEMEABLE_PROPERTIES.dig("chat_pane_bg", :default), theme.color_for("chat_pane_bg")
  end

  test "color_for walks a two-hop chain to the profile side" do
    # chat_topbar_bg -> chat_pane_bg -> pane_bg, with only the far end set.
    theme = Theme.new(user: users(:one), name: "Two hop", colors: { "pane_bg" => "#111111" })
    assert_equal "#111111", theme.color_for("chat_topbar_bg")
  end

  test "color_for stops at the nearest set link in a chain" do
    theme = Theme.new(user: users(:one), name: "Mid chain",
                      colors: { "pane_bg" => "#111111", "chat_pane_bg" => "#222222" })
    assert_equal "#222222", theme.color_for("chat_topbar_bg")
  end

  test "color_for falls back to the default when nothing in the chain is set" do
    theme = Theme.new(user: users(:one), name: "Empty", colors: {})
    assert_equal Theme::THEMEABLE_PROPERTIES.dig("pane_bg", :default), theme.color_for("chat_pane_bg")
  end

  test "every fallback names a real themeable property" do
    Theme::THEMEABLE_PROPERTIES.each do |key, meta|
      next unless meta[:fallback]
      assert Theme::THEMEABLE_PROPERTIES.key?(meta[:fallback]),
        "#{key} falls back to unknown property #{meta[:fallback]}"
    end
  end

  # This is what pins inheritance to one direction: profile keys are always
  # set and terminate every chain, chat keys inherit or override. A fallback
  # added to a profile key would silently make it bidirectional.
  test "only chat properties declare a fallback" do
    with_fallback = Theme::THEMEABLE_PROPERTIES.select { |_, meta| meta[:fallback] }.keys
    non_chat = with_fallback.reject { |key| key.start_with?("chat_") }
    assert_empty non_chat, "non-chat properties must not declare a fallback"
  end

  test "no fallback chain cycles, and every chain ends on a profile key" do
    Theme::THEMEABLE_PROPERTIES.each_key do |key|
      seen = []
      current = key
      while (parent = Theme::THEMEABLE_PROPERTIES.dig(current, :fallback))
        assert_not_includes seen, parent, "fallback chain from #{key} cycles at #{parent}"
        seen << parent
        current = parent
      end
      assert_not current.start_with?("chat_"), "chain from #{key} ends on chat key #{current}"
    end
  end

  test "every chat property has a profile counterpart it renders identically to by default" do
    # The promise that made this shippable without a data migration: an
    # untouched theme resolves every chat key to the same colour its profile
    # counterpart had before the split.
    theme = themes(:dark_forest)
    css = theme.to_css_properties

    Theme::THEMEABLE_PROPERTIES.each do |key, meta|
      next unless key.start_with?("chat_")
      assert_includes css, "--#{key.tr('_', '-')}: #{theme.color_for(meta[:fallback])};",
        "#{key} should render as its inherited colour on an untouched theme"
    end
  end

  test "to_css_properties emits every chat property concretely" do
    css = themes(:dark_forest).to_css_properties
    Theme::THEMEABLE_PROPERTIES.each_key do |key|
      next unless key.start_with?("chat_")
      assert_match(/--#{key.tr('_', '-')}: #\h{6}(\h{2})?;/, css, "#{key} should be emitted as a concrete hex")
    end
  end

  # -- Color validation --

  test "accepts 6-digit hex colors" do
    theme = Theme.new(user: users(:one), name: "Six digit", colors: { page_bg: "#123456" })
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "accepts 8-digit hex colors with alpha" do
    theme = Theme.new(user: users(:one), name: "Eight digit", colors: { page_bg: "#12345678", pane_text: "#aabbccdd" })
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "rejects 7-digit hex colors" do
    theme = Theme.new(user: users(:one), name: "Seven digit", colors: { page_bg: "#1234567" })
    assert_not theme.valid?
    assert_includes theme.errors[:colors].to_sentence, "page_bg"
  end

  test "rejects 5-digit hex colors" do
    theme = Theme.new(user: users(:one), name: "Five digit", colors: { page_bg: "#12345" })
    assert_not theme.valid?
    assert_includes theme.errors[:colors].to_sentence, "page_bg"
  end

  test "rejects hex without hash" do
    theme = Theme.new(user: users(:one), name: "No hash", colors: { page_bg: "123456" })
    assert_not theme.valid?
    assert_includes theme.errors[:colors].to_sentence, "page_bg"
  end

  test "rejects invalid hex characters" do
    theme = Theme.new(user: users(:one), name: "Bad chars", colors: { page_bg: "#gggggg" })
    assert_not theme.valid?
    assert_includes theme.errors[:colors].to_sentence, "page_bg"
  end

  test "to_css includes 8-digit hex with alpha" do
    theme = Theme.new(
      user: users(:one),
      name: "Alpha theme",
      colors: { page_bg: "#12345678", pane_text: "#aabbccff" }
    )
    css = theme.to_css
    assert_includes css, "--page-bg: #12345678;"
    assert_includes css, "--pane-text: #aabbccff;"
  end

  test "to_css_properties includes 8-digit hex with alpha" do
    theme = Theme.new(
      user: users(:one),
      name: "Alpha inline",
      colors: { page_bg: "#00000080", pane_link: "#ff0000ff" }
    )
    css = theme.to_css_properties
    assert_includes css, "--page-bg: #00000080;"
    assert_includes css, "--pane-link: #ff0000ff;"
  end

  # -- Tags --

  test "tags default to empty array" do
    theme = Theme.new(user: users(:one), name: "Tagless", colors: {})
    assert_equal [], theme.tags
  end

  test "TAGS is a non-empty hash" do
    assert_kind_of Hash, Theme::TAGS
    assert Theme::TAGS.any?
  end

  test "valid with known tags" do
    theme = Theme.new(user: users(:one), name: "Tagged", colors: {}, tags: [ "dark", "high-contrast" ])
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "valid with empty tags" do
    theme = Theme.new(user: users(:one), name: "No tags", colors: {}, tags: [])
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "invalid with unknown tag" do
    theme = Theme.new(user: users(:one), name: "Bad tag", colors: {}, tags: [ "unknown-tag" ])
    assert_not theme.valid?
    assert_match "unknown-tag", theme.errors[:tags].to_sentence
  end

  test "fixture dark_forest has expected tags" do
    assert_equal [ "dark", "cool-colours" ], themes(:dark_forest).tags
  end

  test "fixture sunset has expected tags" do
    assert_equal [ "light", "warm-colours" ], themes(:sunset).tags
  end

  # -- Credit & notes --

  test "valid with credit and notes" do
    theme = Theme.new(user: users(:one), name: "Credited", colors: {}, credit: "Dru", notes: "My notes")
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "valid without credit and notes" do
    theme = Theme.new(user: users(:one), name: "Plain", colors: {})
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "credit over 255 characters is invalid" do
    theme = Theme.new(user: users(:one), name: "Long credit", colors: {}, credit: "a" * 256)
    assert_not theme.valid?
    assert_includes theme.errors[:credit], "is too long (maximum is 255 characters)"
  end

  test "credit at exactly 255 characters is valid" do
    theme = Theme.new(user: users(:one), name: "Max credit", colors: {}, credit: "a" * 255)
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  # -- Credit URL --

  test "valid with a https credit_url" do
    theme = Theme.new(user: users(:one), name: "Linked", colors: {}, credit_url: "https://example.com")
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "valid with a http credit_url" do
    theme = Theme.new(user: users(:one), name: "Linked", colors: {}, credit_url: "http://example.com")
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "valid without credit_url" do
    theme = Theme.new(user: users(:one), name: "No link", colors: {})
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "invalid credit_url without scheme" do
    theme = Theme.new(user: users(:one), name: "Bad link", colors: {}, credit_url: "example.com")
    assert_not theme.valid?
    assert_includes theme.errors[:credit_url], "must be a valid http or https URL"
  end

  test "invalid credit_url with ftp scheme" do
    theme = Theme.new(user: users(:one), name: "FTP", colors: {}, credit_url: "ftp://example.com")
    assert_not theme.valid?
    assert_includes theme.errors[:credit_url], "must be a valid http or https URL"
  end

  test "credit_url over 255 characters is invalid" do
    theme = Theme.new(user: users(:one), name: "Long URL", colors: {}, credit_url: "https://" + "a" * 248)
    assert_not theme.valid?
    assert_includes theme.errors[:credit_url], "is too long (maximum is 255 characters)"
  end

  # -- Button border colours --

  test "valid with explicit button border colours" do
    theme = Theme.new(
      user: users(:one), name: "Bordered", colors: {
        primary_button_border: "#58cc9d",
        secondary_button_border: "#58cc9d",
        danger_button_border: "#e6c4cf"
      }
    )
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "color_for returns stored primary_button_border" do
    theme = Theme.new(user: users(:one), name: "B", colors: { "primary_button_border" => "#aabbcc" })
    assert_equal "#aabbcc", theme.color_for("primary_button_border")
  end

  test "color_for falls back to default for primary_button_border" do
    theme = Theme.new(user: users(:one), name: "B", colors: {})
    assert_equal "#4ec59a", theme.color_for("primary_button_border")
  end

  test "color_for falls back to default for secondary_button_border" do
    theme = Theme.new(user: users(:one), name: "B", colors: {})
    assert_equal "#4dbb8f", theme.color_for("secondary_button_border")
  end

  test "color_for falls back to default for danger_button_border" do
    theme = Theme.new(user: users(:one), name: "B", colors: {})
    assert_equal "#d8b5c0", theme.color_for("danger_button_border")
  end

  test "to_css_properties includes all three button border variables" do
    theme = themes(:dark_forest)
    css = theme.to_css_properties
    assert_includes css, "--primary-button-border:"
    assert_includes css, "--secondary-button-border:"
    assert_includes css, "--danger-button-border:"
  end

  test "to_css includes all three button border variables" do
    theme = themes(:dark_forest)
    css = theme.to_css
    assert_includes css, "  --primary-button-border:"
    assert_includes css, "  --secondary-button-border:"
    assert_includes css, "  --danger-button-border:"
  end

  test "THEMEABLE_PROPERTIES includes button border keys" do
    keys = Theme::THEMEABLE_PROPERTIES.keys
    assert_includes keys, "primary_button_border"
    assert_includes keys, "secondary_button_border"
    assert_includes keys, "danger_button_border"
  end

  test "button border properties are in the buttons group" do
    assert_equal :buttons, Theme::THEMEABLE_PROPERTIES.dig("primary_button_border", :group)
    assert_equal :buttons, Theme::THEMEABLE_PROPERTIES.dig("secondary_button_border", :group)
    assert_equal :buttons, Theme::THEMEABLE_PROPERTIES.dig("danger_button_border", :group)
  end

  # -- Shared themes --

  test "admin user can create a shared theme" do
    theme = Theme.new(user: users(:one), name: "Admin shared", colors: {}, shared: true)
    assert users(:one).admin?, "fixture user one should be admin"
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "non-admin user cannot create a shared theme" do
    theme = Theme.new(user: users(:two), name: "Non-admin shared", colors: {}, shared: true)
    assert_not users(:two).admin?
    assert_not theme.valid?
    assert_includes theme.errors[:shared], "can only be set by admins"
  end

  test "non-admin theme with shared false is valid" do
    theme = Theme.new(user: users(:two), name: "Non-admin personal", colors: {}, shared: false)
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "shared scope returns only shared themes" do
    shared = Theme.shared
    assert_includes shared, themes(:ocean_shared)
    assert_not_includes shared, themes(:dark_forest)
    assert_not_includes shared, themes(:sunset)
  end

  test "personal scope returns only non-shared themes" do
    personal = Theme.personal
    assert_not_includes personal, themes(:ocean_shared)
    assert_includes personal, themes(:dark_forest)
    assert_includes personal, themes(:sunset)
  end

  # -- Default theme --

  test "site_default can only be set on shared themes" do
    theme = Theme.new(user: users(:one), name: "Personal Default", colors: {}, shared: false, site_default: true)
    assert_not theme.valid?
    assert_includes theme.errors[:site_default], "can only be set on shared themes"
  end

  test "site_default on a shared theme is valid" do
    theme = Theme.new(user: users(:one), name: "Shared Default", colors: {}, shared: true, site_default: true)
    assert theme.valid?, theme.errors.full_messages.inspect
  end

  test "site_default_theme returns the default theme" do
    Rails.cache.clear
    assert_equal themes(:default_shared), Theme.site_default_theme
  end

  test "site_default_theme returns nil when no default is set" do
    Rails.cache.clear
    themes(:default_shared).update!(site_default: false)
    assert_nil Theme.site_default_theme
  end

  test "setting site_default clears it on other themes" do
    Rails.cache.clear
    themes(:ocean_shared).update!(site_default: true)
    assert themes(:ocean_shared).reload.site_default?
    assert_not themes(:default_shared).reload.site_default?
  end

  test "destroying the default theme busts the cache" do
    Rails.cache.clear
    # Warm the cache
    Theme.site_default_theme
    # Destroy the default theme — cache should be busted
    themes(:default_shared).destroy
    assert_nil Theme.site_default_theme
  end

  # -- Export --

  test "to_export_hash includes expected keys" do
    theme = themes(:dark_forest)
    hash = theme.to_export_hash
    assert_equal Theme::CURRENT_EXPORT_VERSION, hash[:plural_profiles_theme]
    assert_equal "Dark Forest", hash[:name]
    assert_kind_of Hash, hash[:colors]
    assert_equal "#0e2e24", hash[:colors]["page_bg"]
    assert_equal [ "dark", "cool-colours" ], hash[:tags]
    assert_equal "Verdant Studio", hash[:credit]
    assert_equal "https://example.com/verdant", hash[:credit_url]
  end

  test "to_export_hash omits nil values via compact" do
    theme = Theme.new(user: users(:one), name: "Minimal", colors: { "page_bg" => "#000000" })
    hash = theme.to_export_hash
    assert_equal Theme::CURRENT_EXPORT_VERSION, hash[:plural_profiles_theme]
    assert_equal "Minimal", hash[:name]
    assert_not hash.key?(:credit)
    assert_not hash.key?(:credit_url)
    assert_not hash.key?(:notes)
  end

  test "to_export_hash includes background options" do
    theme = themes(:dark_forest)
    theme.background_repeat = "no-repeat"
    theme.background_size = "cover"
    theme.background_position = "top"
    theme.background_attachment = "fixed"
    hash = theme.to_export_hash
    assert_equal "no-repeat", hash[:background_repeat]
    assert_equal "cover", hash[:background_size]
    assert_equal "top", hash[:background_position]
    assert_equal "fixed", hash[:background_attachment]
  end

  test "to_export_json produces valid JSON" do
    theme = themes(:dark_forest)
    json = theme.to_export_json
    parsed = JSON.parse(json)
    assert_equal Theme::CURRENT_EXPORT_VERSION, parsed["plural_profiles_theme"]
    assert_equal "Dark Forest", parsed["name"]
    assert_equal "#0e2e24", parsed["colors"]["page_bg"]
  end

  # -- Import --

  test "import_attributes_from_json parses valid JSON correctly" do
    json = {
      plural_profiles_theme: 2,
      name: "Imported",
      colors: { page_bg: "#112233", pane_text: "#aabbcc" },
      tags: [ "dark", "cool-colours" ],
      credit: "Test Author",
      credit_url: "https://example.com",
      notes: "Some notes",
      background_repeat: "no-repeat",
      background_size: "cover",
      background_position: "top",
      background_attachment: "fixed"
    }.to_json

    attrs = Theme.import_attributes_from_json(json)
    assert_equal "Imported", attrs[:name]
    assert_equal({ "page_bg" => "#112233", "pane_text" => "#aabbcc" }, attrs[:colors])
    assert_equal [ "dark", "cool-colours" ], attrs[:tags]
    assert_equal "Test Author", attrs[:credit]
    assert_equal "https://example.com", attrs[:credit_url]
    assert_equal "Some notes", attrs[:notes]
    assert_equal "no-repeat", attrs[:background_repeat]
    assert_equal "cover", attrs[:background_size]
    assert_equal "top", attrs[:background_position]
    assert_equal "fixed", attrs[:background_attachment]
  end

  test "import_attributes_from_json upgrades legacy heading/text/link colours to header/pane variants" do
    json = {
      plural_profiles_theme: 1,
      colors: { page_bg: "#112233", heading: "#111111", text: "#222222", link: "#333333" }
    }.to_json

    attrs = Theme.import_attributes_from_json(json)
    assert_equal "#112233", attrs[:colors]["page_bg"]
    assert_equal "#111111", attrs[:colors]["header_title_text"]
    assert_equal "#111111", attrs[:colors]["pane_title_text"]
    assert_equal "#222222", attrs[:colors]["header_text"]
    assert_equal "#222222", attrs[:colors]["pane_text"]
    assert_equal "#333333", attrs[:colors]["header_link"]
    assert_equal "#333333", attrs[:colors]["pane_link"]
    assert_not attrs[:colors].key?("heading")
    assert_not attrs[:colors].key?("text")
    assert_not attrs[:colors].key?("link")
  end

  test "import_attributes_from_json raises on invalid JSON" do
    error = assert_raises(RuntimeError) do
      Theme.import_attributes_from_json("not json at all")
    end
    assert_match(/Invalid JSON/, error.message)
  end

  test "import_attributes_from_json raises on missing version marker" do
    error = assert_raises(RuntimeError) do
      Theme.import_attributes_from_json('{"name": "No version"}')
    end
    assert_match(/Not a Plural Profiles theme/, error.message)
  end

  test "import_attributes_from_json raises on an unsupported future version" do
    error = assert_raises(RuntimeError) do
      Theme.import_attributes_from_json({ plural_profiles_theme: 99, name: "Future" }.to_json)
    end
    assert_match(/Unsupported theme version: 99/, error.message)
  end

  test "migrate_legacy_colors upgrades heading/text/link without clobbering existing new keys" do
    colors = { "heading" => "#111111", "pane_title_text" => "#existing" }
    migrated = Theme.migrate_legacy_colors(colors)
    assert_equal "#existing", migrated["pane_title_text"]
    assert_equal "#111111", migrated["header_title_text"]
  end

  test "import_attributes_from_json ignores unknown keys" do
    json = { plural_profiles_theme: 1, name: "Valid", unknown_key: "ignored", colors: {} }.to_json
    attrs = Theme.import_attributes_from_json(json)
    assert_equal "Valid", attrs[:name]
    assert_not attrs.key?(:unknown_key)
  end

  test "import_attributes_from_json filters colours to known keys only" do
    json = {
      plural_profiles_theme: 1,
      colors: { page_bg: "#112233", invented_colour: "#ffffff" }
    }.to_json
    attrs = Theme.import_attributes_from_json(json)
    assert_equal({ "page_bg" => "#112233" }, attrs[:colors])
  end

  test "import_attributes_from_json filters tags to known values only" do
    json = { plural_profiles_theme: 1, tags: [ "dark", "invented-tag" ] }.to_json
    attrs = Theme.import_attributes_from_json(json)
    assert_equal [ "dark" ], attrs[:tags]
  end

  test "import_attributes_from_json ignores invalid background options" do
    json = {
      plural_profiles_theme: 1,
      background_repeat: "invalid",
      background_size: "auto"
    }.to_json
    attrs = Theme.import_attributes_from_json(json)
    assert_not attrs.key?(:background_repeat)
    assert_equal "auto", attrs[:background_size]
  end

  test "round-trip export and import preserves data" do
    theme = themes(:dark_forest)
    theme.update!(notes: "Round trip test", background_repeat: "no-repeat", background_size: "cover")
    json = theme.to_export_json
    attrs = Theme.import_attributes_from_json(json)
    assert_equal theme.name, attrs[:name]
    assert_equal theme.colors, attrs[:colors]
    assert_equal theme.tags, attrs[:tags]
    assert_equal theme.credit, attrs[:credit]
    assert_equal theme.credit_url, attrs[:credit_url]
    assert_equal "Round trip test", attrs[:notes]
    assert_equal "no-repeat", attrs[:background_repeat]
    assert_equal "cover", attrs[:background_size]
  end
  # ── Chat colours in import/export ───────────────────────────────────────

  test "a theme with no chat overrides exports no chat keys" do
    theme = Theme.new(user: users(:one), name: "Profile only", colors: { "pane_bg" => "#112233" })
    exported = theme.to_export_hash

    assert_equal Theme::CURRENT_EXPORT_VERSION, exported[:plural_profiles_theme]
    assert_empty exported[:colors].keys.select { |key| key.start_with?("chat_") }
  end

  test "a theme with chat overrides exports only the ones that were set" do
    theme = Theme.new(user: users(:one), name: "Half designed",
                      colors: { "pane_bg" => "#112233", "chat_rail_bg" => "#ff0000" })
    exported = theme.to_export_hash

    assert_equal "#ff0000", exported[:colors]["chat_rail_bg"]
    assert_not exported[:colors].key?("chat_pane_bg")
  end

  test "importing a v2 export leaves every chat colour inherited" do
    # The reason no v2 -> v3 upgrade step exists: "absent" already means the
    # right thing, so an older export arrives as a fully-inherited chat palette.
    json = {
      plural_profiles_theme: 2,
      name: "Old export",
      colors: { pane_bg: "#112233", pane_text: "#445566" }
    }.to_json

    attrs = Theme.import_attributes_from_json(json)

    assert_empty attrs[:colors].keys.select { |key| key.start_with?("chat_") }

    theme = Theme.new(user: users(:one), **attrs)
    assert_equal "#112233", theme.color_for("chat_pane_bg"), "chat should follow the imported profile colour"
  end

  test "importing a v3 export keeps its chat overrides" do
    json = {
      plural_profiles_theme: 3,
      name: "New export",
      colors: { pane_bg: "#112233", chat_rail_bg: "#ff0000" }
    }.to_json

    attrs = Theme.import_attributes_from_json(json)
    theme = Theme.new(user: users(:one), **attrs)

    assert_equal "#ff0000", theme.color_for("chat_rail_bg")
    assert_equal "#112233", theme.color_for("chat_pane_bg")
  end

  test "importing a v1 export upgrades through both splits at once" do
    # v1 keys land on the v2 header/pane keys, which the chat keys then inherit
    # from — the two upgrades compose without a v1 -> v3 path of their own.
    json = { plural_profiles_theme: 1, name: "Ancient", colors: { text: "#445566" } }.to_json

    attrs = Theme.import_attributes_from_json(json)
    theme = Theme.new(user: users(:one), **attrs)

    assert_equal "#445566", theme.color_for("pane_text")
    assert_equal "#445566", theme.color_for("chat_pane_text")
  end

  test "a version above the current one is still rejected" do
    json = { plural_profiles_theme: Theme::CURRENT_EXPORT_VERSION + 1, name: "Future" }.to_json
    error = assert_raises(RuntimeError) { Theme.import_attributes_from_json(json) }
    assert_match "Unsupported theme version", error.message
  end

  test "overridden? distinguishes a set colour from an inherited one" do
    theme = Theme.new(user: users(:one), name: "Mixed",
                      colors: { "pane_bg" => "#112233", "chat_rail_bg" => "#ff0000" })

    assert theme.overridden?("chat_rail_bg")
    assert_not theme.overridden?("chat_pane_bg")
  end

  test "FALLBACK_CHAIN matches the fallbacks declared on the properties" do
    # The editor resolves inherited colours in JS from this map, so it drifting
    # from THEMEABLE_PROPERTIES would show up as the wrong swatch rather than
    # as an error.
    expected = Theme::THEMEABLE_PROPERTIES.filter_map { |key, meta| [ key, meta[:fallback] ] if meta[:fallback] }.to_h
    assert_equal expected, Theme::FALLBACK_CHAIN
  end
end
