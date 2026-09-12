require "uri"

class Theme < ApplicationRecord
  belongs_to :user

  has_one_attached :background_image

  scope :shared, -> { where(shared: true) }
  scope :personal, -> { where(shared: false) }

  validates :name, presence: true, length: { maximum: 255 }
  validates :credit, length: { maximum: 255 }, allow_nil: true
  validates :credit_url, length: { maximum: 255 }, allow_blank: true
  validates :background_repeat, inclusion: { in: ->(_) { BACKGROUND_REPEAT_OPTIONS } }
  validates :background_size, inclusion: { in: ->(_) { BACKGROUND_SIZE_OPTIONS } }
  validates :background_position, inclusion: { in: ->(_) { BACKGROUND_POSITION_OPTIONS } }
  validates :background_attachment, inclusion: { in: ->(_) { BACKGROUND_ATTACHMENT_OPTIONS } }
  validate :credit_url_must_be_http_url
  validate :only_admin_can_share
  validate :site_default_must_be_shared
  validate :colors_is_a_hash
  validate :colors_keys_are_known
  validate :colors_values_are_hex
  validate :tags_are_known
  validate :background_image_content_type_allowed
  validate :background_image_size_allowed
  validate :background_image_dimensions_allowed

  before_validation :normalize_colors_keys
  before_validation :normalize_tags
  before_validation :normalize_credit_url

  before_save :clear_other_defaults, if: -> { site_default? && site_default_changed? }

  after_save :bust_default_theme_cache, if: -> { saved_change_to_site_default? }
  after_destroy :bust_default_theme_cache, if: :site_default?

  BACKGROUND_IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  BACKGROUND_IMAGE_MAX_SIZE = 2.megabytes
  BACKGROUND_IMAGE_MAX_DIMENSION = 4000

  BACKGROUND_REPEAT_OPTIONS = %w[repeat repeat-x repeat-y no-repeat].freeze
  BACKGROUND_SIZE_OPTIONS = %w[auto cover contain].freeze
  BACKGROUND_POSITION_OPTIONS = %w[center top bottom left right].freeze
  BACKGROUND_ATTACHMENT_OPTIONS = %w[scroll fixed].freeze

  TAGS = {
    "bright"           => "Bright",
    "light"            => "Light",
    "dark"             => "Dark",
    "super-contrast"   => "Super contrast",
    "high-contrast"    => "High contrast",
    "mid-contrast"     => "Mid contrast",
    "low-contrast"     => "Low contrast",
    "warm-colours"     => "Warm colours",
    "cool-colours"     => "Cool colours",
    "blind-low-vision" => "Blind/low vision"
  }.freeze

  def colors=(value)
    super(value.is_a?(Hash) ? value.transform_keys(&:to_s) : value)
  end

  def normalize_credit_url
    return if credit_url.nil?

    stripped = credit_url.strip
    self.credit_url = stripped.presence
  end

  def credit_url_must_be_http_url
    return if credit_url.blank?

    uri = URI.parse(credit_url)

    unless uri.is_a?(URI::HTTP) && uri.host.present?
      errors.add(:credit_url, "must be a valid http or https URL")
    end
  rescue URI::InvalidURIError
    errors.add(:credit_url, "must be a valid http or https URL")
  end

  # The CSS custom properties that can be themed, mapped to their default values.
  # Properties that reference other variables (e.g. --input-text: var(--pane-text))
  # are resolved to the concrete colour they point to so the colour picker always
  # starts with a hex value.
  #
  # Every text colour is paired with the specific background it's meant to sit
  # on (header_* vs pane_*) rather than shared across both — a colour that
  # only ever appears on one background can't accidentally vanish against the
  # other. See LEGACY_COLOR_ALIASES for the pre-split heading/text/link keys
  # this replaced.
  THEMEABLE_PROPERTIES = {
    "page_bg"                 => { label: "Page background",           default: "#0b221b", group: :page    },

    "header_bg"               => { label: "Header background",         default: "#0e2e24", group: :header  },
    "header_title_text"       => { label: "Header title text",         default: "#5ea389", group: :header  },
    "header_text"             => { label: "Header text",               default: "#5ea389", group: :header  },
    "header_link"             => { label: "Header links",              default: "#3ab580", group: :header  },

    "pane_bg"                 => { label: "Pane background",           default: "#133b2f", group: :pane    },
    "pane_border"             => { label: "Pane border",               default: "#02120e", group: :pane    },
    "pane_title_text"         => { label: "Pane title text",           default: "#5ea389", group: :pane    },
    "pane_text"               => { label: "Pane text",                 default: "#5ea389", group: :pane    },
    "pane_link"               => { label: "Pane links",                default: "#3ab580", group: :pane    },
    "spoiler"                 => { label: "Spoiler background",        default: "#3A3A3A", group: :pane    },

    "primary_button_bg"       => { label: "Main button background",    default: "#12684e", group: :buttons },
    "primary_button_text"     => { label: "Main button text",          default: "#4ec59a", group: :buttons },
    "primary_button_border"   => { label: "Main button border",        default: "#4ec59a", group: :buttons },
    "secondary_button_bg"     => { label: "Default button background", default: "#155642", group: :buttons },
    "secondary_button_text"   => { label: "Default button text",       default: "#4dbb8f", group: :buttons },
    "secondary_button_border" => { label: "Default button border",     default: "#4dbb8f", group: :buttons },
    "danger_button_bg"        => { label: "Danger button background",  default: "#9d1d46", group: :buttons },
    "danger_button_text"      => { label: "Danger button text",        default: "#d8b5c0", group: :buttons },
    "danger_button_border"    => { label: "Danger button border",      default: "#d8b5c0", group: :buttons },
    "input_label"             => { label: "Input labels",              default: "#599981", group: :forms   },
    "input_bg"                => { label: "Input background",          default: "#263a2e", group: :forms   },
    "input_border"            => { label: "Input border",              default: "#3c6f5f", group: :forms   },
    "input_text"              => { label: "Input text",                default: "#5ea389", group: :forms   },
    "notice_bg"               => { label: "Notice background",         default: "#133b2f", group: :flash   },
    "notice_border"           => { label: "Notice border",             default: "#5ea389", group: :flash   },
    "notice_text"             => { label: "Notice text",               default: "#5ea389", group: :flash   },
    "alert_bg"                => { label: "Alert background",          default: "#11694a", group: :flash   },
    "alert_border"            => { label: "Alert border",              default: "#58cc9d", group: :flash   },
    "alert_text"              => { label: "Alert text",                default: "#58cc9d", group: :flash   },
    "warning_bg"              => { label: "Warning background",        default: "#a81d49", group: :flash   },
    "warning_border"          => { label: "Warning border",            default: "#e6c4cf", group: :flash   },
    "warning_text"            => { label: "Warning text",              default: "#e6c4cf", group: :flash   },

    # ── Chat ────────────────────────────────────────────────────────────────
    # Chat has its own palette because its regions don't map onto the profile
    # page's. Chat needs the server rail, the divider bars, the channel list
    # and the message pane to be four separately-coloured surfaces, where
    # profile pages only ever have "page" and "pane" — so on profile colours
    # alone the rail is welded to the divider (both --pane-border) and the
    # channel list to the message pane (both --pane-bg), with no way to part
    # them.
    #
    # Every key here carries a `fallback:` naming its profile-page equivalent,
    # and is stored only when the designer explicitly sets it (see color_for).
    # An untouched chat key therefore tracks its profile counterpart forever,
    # which is why this shipped with no data migration: each `default:` below
    # is exactly what that region rendered before the split, so an existing
    # theme looks the same afterwards.
    #
    # `fallback:` appears on chat keys only. Inheritance runs one way —
    # profile is always set, chat inherits or overrides — and it resolves
    # *within* a single theme: color_for never consults another Theme row.
    "chat_header_bg"           => { label: "Header background",        default: "#0e2e24", group: :chat_header,   fallback: "header_bg" },
    "chat_header_title_text"   => { label: "Header title text",        default: "#5ea389", group: :chat_header,   fallback: "header_title_text" },
    "chat_header_text"         => { label: "Header text",              default: "#5ea389", group: :chat_header,   fallback: "header_text" },
    "chat_header_link"         => { label: "Header links",             default: "#3ab580", group: :chat_header,   fallback: "header_link" },

    "chat_rail_bg"             => { label: "Server sidebar background", default: "#02120e", group: :chat_rail,    fallback: "pane_border" },
    "chat_rail_text"           => { label: "Server sidebar text",      default: "#5ea389", group: :chat_rail,     fallback: "pane_text" },
    "chat_rail_active"         => { label: "Active server ring",       default: "#5ea389", group: :chat_rail,     fallback: "pane_title_text" },
    "chat_rail_link"           => { label: "Add server button",        default: "#3ab580", group: :chat_rail,     fallback: "pane_link" },
    # One per surface: the rail dot sits on chat_rail_bg and the channel-list
    # dot on chat_sidebar_bg, which a designer may well have coloured very
    # differently, so a single key would force a compromise on one of them.
    # They follow pane_text rather than the primary button's text colour they
    # used to borrow — button text is often near-black, which left the dots
    # invisible, whereas a theme's pane text is by definition legible.
    "chat_rail_unread_dot"     => { label: "Unread dots",              default: "#5ea389", group: :chat_rail,     fallback: "pane_text" },

    "chat_divider"             => { label: "Divider bars",             default: "#02120e", group: :chat_dividers, fallback: "pane_border" },

    "chat_sidebar_bg"          => { label: "Channel list background",  default: "#133b2f", group: :chat_sidebar,  fallback: "pane_bg" },
    "chat_sidebar_text"        => { label: "Channel list text",        default: "#5ea389", group: :chat_sidebar,  fallback: "pane_text" },
    "chat_sidebar_title_text"  => { label: "Channel list title text",  default: "#5ea389", group: :chat_sidebar,  fallback: "pane_title_text" },
    # Channel names are bare links with no colour rule of their own, so they
    # have always taken the link colour rather than the pane text colour.
    "chat_sidebar_link"        => { label: "Channel names & links",    default: "#3ab580", group: :chat_sidebar,  fallback: "pane_link" },
    "chat_sidebar_unread_dot"  => { label: "Unread dots",              default: "#5ea389", group: :chat_sidebar,  fallback: "pane_text" },

    "chat_topbar_bg"           => { label: "Chat header background",   default: "#133b2f", group: :chat_topbar,   fallback: "pane_bg" },
    "chat_topbar_text"         => { label: "Chat header text",         default: "#5ea389", group: :chat_topbar,   fallback: "pane_text" },
    "chat_topbar_title_text"   => { label: "Chat header title text",   default: "#5ea389", group: :chat_topbar,   fallback: "pane_title_text" },

    "chat_pane_bg"             => { label: "Message pane background",  default: "#133b2f", group: :chat_pane,     fallback: "pane_bg" },
    "chat_pane_text"           => { label: "Message pane text",        default: "#5ea389", group: :chat_pane,     fallback: "pane_text" },
    "chat_pane_title_text"     => { label: "Message author names",     default: "#5ea389", group: :chat_pane,     fallback: "pane_title_text" },
    "chat_pane_link"           => { label: "Message links",            default: "#3ab580", group: :chat_pane,     fallback: "pane_link" },
    "chat_spoiler"             => { label: "Spoiler background",       default: "#3A3A3A", group: :chat_pane,     fallback: "spoiler" },

    "chat_composer_bg"         => { label: "Composer background",      default: "#133b2f", group: :chat_composer, fallback: "pane_bg" },
    "chat_composer_text"       => { label: "Composer text",            default: "#5ea389", group: :chat_composer, fallback: "pane_text" },
    # The one key with no real profile counterpart: .profile-picker was a
    # color-mix of --pane-bg and --page-bg before the split, so its default is
    # that mix resolved against the stock theme. It follows pane_bg, the nearer
    # half of that mix.
    "chat_composer_highlight"  => { label: "Posting-as highlight",     default: "#12372c", group: :chat_composer, fallback: "pane_bg" },
    "chat_input_bg"            => { label: "Composer input background", default: "#263a2e", group: :chat_composer, fallback: "input_bg" },
    "chat_input_border"        => { label: "Composer input border",    default: "#3c6f5f", group: :chat_composer, fallback: "input_border" },
    "chat_input_text"          => { label: "Composer input text",      default: "#5ea389", group: :chat_composer, fallback: "input_text" }
  }.freeze

  PROPERTY_GROUPS = {
    page:          "Page",
    header:        "Header",
    pane:          "Pane",
    forms:         "Form controls",
    buttons:       "Buttons",
    flash:         "Flash messages",
    chat_header:   "Header bar",
    chat_rail:     "Server sidebar",
    chat_dividers: "Divider bars",
    chat_sidebar:  "Channel sidebar",
    chat_topbar:   "Chat header",
    chat_pane:     "Message pane",
    chat_composer: "Composer bar"
  }.freeze

  # The two top-level halves of the theme designer. Profile is primary (every
  # key always has a value); chat is secondary (keys are stored only when
  # overridden). The form renders one accordion per section, each containing
  # its groups in this order.
  PROPERTY_SECTIONS = {
    profile: { label: "Profile pages", groups: %i[page header pane forms buttons flash] },
    # No chat page background: chat fills the window, so the body colour is
    # only ever visible behind the cards on the plain chat pages (server list,
    # settings, invites), which use the profile page background like every
    # other page in the app.
    # Dividers last: they're the seams between the other regions, so they're
    # the thing you reach for once those are settled.
    chat:    { label: "Chat",          groups: %i[chat_header chat_rail chat_sidebar chat_topbar
                                                  chat_pane chat_composer chat_dividers] }
  }.freeze

  # Maps each pre-location-split colour key to the new key(s) it was folded
  # into, so a colour used on both the header and the pane keeps working the
  # same way it always did until someone edits the theme. Applied whenever a
  # colours hash might still be in the old shape: importing a v1 JSON export,
  # pasting a legacy CSS :root { } block, or reading a not-yet-migrated
  # database row. New-key values, if already present, always win.
  LEGACY_COLOR_ALIASES = {
    "heading" => %w[header_title_text pane_title_text],
    "text"    => %w[header_text pane_text],
    "link"    => %w[header_link pane_link]
  }.freeze

  # CSS custom properties that are derived from a text colour at render time,
  # mapped to the property they derive from and their color-mix percentage.
  # Both to_css_properties (Ruby) and the theme-designer Stimulus controller
  # (JS, via a data attribute) read from this single source so the formulas
  # stay in sync.
  #
  # These are the only derived values needing a chat twin, because they're the
  # only ones declared as custom properties on :root — see to_css_properties
  # for why that matters. Every other tint in the stylesheet is an inline
  # color-mix() in an ordinary property, which re-resolves per element, so
  # those just reference --chat-pane-text directly.
  DERIVED_TEXT_PROPERTIES = {
    "tree-guide"                     => { source: "pane_text",      percent: 30 },
    "avatar-placeholder-border"      => { source: "pane_text",      percent: 50 },
    "chat-tree-guide"                => { source: "chat_pane_text", percent: 30 },
    "chat-avatar-placeholder-border" => { source: "chat_pane_text", percent: 50 }
  }.freeze

  SWATCH_PROPERTIES = %w[page_bg pane_bg pane_title_text pane_link primary_button_bg].freeze

  # property => the property it inherits from, for every key that has one.
  # Handed to the theme designer as JSON so the JS can resolve an inherited
  # colour by walking the same chain color_for walks, rather than keeping a
  # second copy of the relationships.
  FALLBACK_CHAIN = THEMEABLE_PROPERTIES.filter_map { |key, meta|
    [ key, meta[:fallback] ] if meta[:fallback]
  }.to_h.freeze

  # Whether the designer explicitly set this property, as opposed to leaving it
  # to inherit. The editor uses this to pick each chat colour's initial
  # inherit/override state; "inherited" is simply the absence of a stored value.
  def overridden?(property)
    colors&.dig(property.to_s).present?
  end

  # Returns the colour for a property: the stored value if the designer set
  # one, else the stored value of the profile colour it follows, else the
  # property's own default.
  #
  # Every fallback points straight at a profile key — chat colours never follow
  # other chat colours, which would make "what is this actually following?" a
  # question you had to trace rather than read. A test enforces that, which is
  # what lets this be a single lookup rather than a walk.
  #
  # Resolution stays inside this theme: a fallback never reads another Theme
  # row, so a server or channel theme with no chat colours of its own inherits
  # from *its own* profile colours rather than deferring to another theme.
  def color_for(property)
    key = property.to_s
    stored = colors&.dig(key)
    return stored if stored.present?

    meta = THEMEABLE_PROPERTIES[key]
    return nil unless meta

    if (parent = meta[:fallback])
      inherited = colors&.dig(parent)
      return inherited if inherited.present?
    end

    meta[:default]
  end

  # Upgrades a colours hash that may still use the pre-location-split keys
  # (heading/text/link) into the current schema. See LEGACY_COLOR_ALIASES.
  def self.migrate_legacy_colors(colors)
    return colors unless colors.is_a?(Hash)

    migrated = colors.dup
    LEGACY_COLOR_ALIASES.each do |old_key, new_keys|
      next unless colors.key?(old_key)

      new_keys.each { |new_key| migrated[new_key] ||= colors[old_key] }
    end
    migrated
  end

  def swatch_colors
    SWATCH_PROPERTIES.map { |prop| color_for(prop) }
  end

  # Generates a CSS string of custom property overrides
  def to_css_properties
    # --tree-guide and --avatar-placeholder-border (and their --chat-* twins)
    # are declared on :root as
    # color-mix(in srgb, var(--pane-text) …).  Per the CSS custom properties spec
    # (https://www.w3.org/TR/css-variables-1/#syntax), a custom property's value
    # is inherited as an *unresolved* token sequence, so var(--pane-text) inside
    # the inherited value ought to re-resolve against each element's own
    # --pane-text. In practice, in every tested browser (Chromium ≥119, Firefox
    # ≥120, Safari ≥17) color-mix() containing a var() reference inside a custom
    # property value is resolved at the element where the property is *declared*
    # (:root), not re-resolved at each inheriting element.  As a result,
    # overriding --pane-text on body via inline style does not update the
    # already-resolved --tree-guide value that descendants inherit from :root.
    # We work around this by emitting an explicit, pre-resolved value here,
    # substituting the concrete theme colour in place of var(--pane-text).
    derived = DERIVED_TEXT_PROPERTIES.map { |css_prop, meta|
      source_color = color_for(meta[:source])
      "--#{css_prop}: color-mix(in srgb, #{source_color} #{meta[:percent]}%, transparent);"
    }

    props = THEMEABLE_PROPERTIES.keys.filter_map { |prop|
      value = color_for(prop)
      css_prop = "--#{prop.tr('_', '-')}"
      "#{css_prop}: #{value};"
    }

    (props + derived).join(" ")
  end

  # Generates a full CSS block suitable for copy/paste
  def to_css
    lines = THEMEABLE_PROPERTIES.keys.map { |prop|
      value = color_for(prop)
      css_prop = "--#{prop.tr('_', '-')}"
      "  #{css_prop}: #{value};"
    }
    ":root {\n#{lines.join("\n")}\n}"
  end

  # Returns the background CSS properties as an inline style string.
  # image_url must be pre-generated by the caller (requires view/controller context).
  def background_css_properties(image_url)
    return "" unless image_url.present?

    [
      "background-image: url('#{image_url}');",
      "background-repeat: #{background_repeat};",
      "background-size: #{background_size};",
      "background-position: #{background_position};",
      "background-attachment: #{background_attachment};"
    ].join(" ")
  end

  # The plural_profiles_theme version marker in exported JSON. Bump this
  # whenever THEMEABLE_PROPERTIES keys are renamed or restructured, and add
  # the old shape to import_attributes_from_json's upgrade path (see
  # LEGACY_COLOR_ALIASES for the v1 -> v2 header/pane text-colour split).
  #
  # v3 added the chat_* keys. There is deliberately no v2 -> v3 upgrade step:
  # the keys are purely additive, and "absent" already means the right thing
  # for a v2 export — inherit from the profile colour — so an older theme
  # imports as a fully-inherited chat palette with no conversion at all.
  CURRENT_EXPORT_VERSION = 3

  # Returns a hash representation of the theme suitable for JSON export.
  # Includes all non-image theme data; background image is excluded.
  def to_export_hash
    {
      plural_profiles_theme: CURRENT_EXPORT_VERSION,
      name: name,
      colors: colors,
      tags: tags,
      credit: credit,
      credit_url: credit_url,
      notes: notes,
      background_repeat: background_repeat,
      background_size: background_size,
      background_position: background_position,
      background_attachment: background_attachment
    }.compact
  end

  # Returns a pretty-printed JSON string for export.
  def to_export_json
    JSON.pretty_generate(to_export_hash)
  end

  # Parses a JSON string and returns a hash of importable attributes.
  # Unknown keys are silently ignored; values are validated against allowed lists.
  def self.import_attributes_from_json(json_string)
    data = JSON.parse(json_string)
    version = data.is_a?(Hash) ? data["plural_profiles_theme"] : nil
    raise "Not a Plural Profiles theme" unless version.is_a?(Integer)
    raise "Unsupported theme version: #{version}" unless version.between?(1, CURRENT_EXPORT_VERSION)

    attrs = {}
    attrs[:name] = data["name"] if data["name"].present?
    attrs[:colors] = migrate_legacy_colors(data["colors"]).slice(*THEMEABLE_PROPERTIES.keys) if data["colors"].is_a?(Hash)
    attrs[:tags] = (data["tags"] & TAGS.keys) if data["tags"].is_a?(Array)
    attrs[:credit] = data["credit"] if data.key?("credit")
    attrs[:credit_url] = data["credit_url"] if data.key?("credit_url")
    attrs[:notes] = data["notes"] if data.key?("notes")
    attrs[:background_repeat] = data["background_repeat"] if BACKGROUND_REPEAT_OPTIONS.include?(data["background_repeat"])
    attrs[:background_size] = data["background_size"] if BACKGROUND_SIZE_OPTIONS.include?(data["background_size"])
    attrs[:background_position] = data["background_position"] if BACKGROUND_POSITION_OPTIONS.include?(data["background_position"])
    attrs[:background_attachment] = data["background_attachment"] if BACKGROUND_ATTACHMENT_OPTIONS.include?(data["background_attachment"])
    attrs
  rescue JSON::ParserError
    raise "Invalid JSON"
  end

  def self.site_default_theme
    Rails.cache.fetch("site_default_theme", expires_in: 5.minutes) do
      shared.find_by(site_default: true)
    end
  end

  private

    def only_admin_can_share
      if shared? && (new_record? || shared_changed?) && !user&.admin?
        errors.add(:shared, "can only be set by admins")
      end
    end

    def site_default_must_be_shared
      if site_default? && !shared?
        errors.add(:site_default, "can only be set on shared themes")
      end
    end

    def clear_other_defaults
      Theme.where(site_default: true).where.not(id: id).update_all(site_default: false)
    end

    def bust_default_theme_cache
      Rails.cache.delete("site_default_theme")
    end

    HEX_COLOR_PATTERN = /\A#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?\z/

    def normalize_colors_keys
      self.colors = colors.transform_keys(&:to_s) if colors.is_a?(Hash)
    end

    def normalize_tags
      self.tags = [] if tags.nil?
    end

    def colors_is_a_hash
      errors.add(:colors, "must be a hash") unless colors.is_a?(Hash)
    end

    def colors_keys_are_known
      return unless colors.is_a?(Hash)

      unknown = colors.transform_keys(&:to_s).keys - THEMEABLE_PROPERTIES.keys
      if unknown.any?
        errors.add(:colors, "contains unknown keys: #{unknown.join(', ')}")
      end
    end

    def colors_values_are_hex
      return unless colors.is_a?(Hash)

      colors.transform_keys(&:to_s).each do |key, value|
        unless value.to_s.match?(HEX_COLOR_PATTERN)
          errors.add(:colors, "value for '#{key}' is not a valid hex colour (expected #RRGGBB or #RRGGBBAA)")
        end
      end
    end

    def tags_are_known
      unless tags.is_a?(Array)
        errors.add(:tags, "must be an array")
        return
      end

      unknown = tags - TAGS.keys
      errors.add(:tags, "contains unknown values: #{unknown.join(', ')}") if unknown.any?
    end

    def background_image_content_type_allowed
      return unless background_image.attached?
      unless background_image.blob.content_type.in?(BACKGROUND_IMAGE_CONTENT_TYPES)
        errors.add(:background_image, "must be a JPG/JPEG, PNG, or WebP image")
      end
    end

    def background_image_size_allowed
      return unless background_image.attached?
      if background_image.blob.byte_size > BACKGROUND_IMAGE_MAX_SIZE
        errors.add(:background_image, "must be 2 MB or less")
      end
    end

    def background_image_dimensions_allowed
      return unless background_image.attached?
      width, height = ImageDimensions.for(background_image)
      return if width.nil?
      if width > BACKGROUND_IMAGE_MAX_DIMENSION || height > BACKGROUND_IMAGE_MAX_DIMENSION
        errors.add(:background_image, "must be #{BACKGROUND_IMAGE_MAX_DIMENSION}×#{BACKGROUND_IMAGE_MAX_DIMENSION} pixels or smaller")
      end
    end
end
