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
    "warning_text"            => { label: "Warning text",              default: "#e6c4cf", group: :flash   }
  }.freeze

  PROPERTY_GROUPS = {
    page:    "Page",
    header:  "Header",
    pane:    "Pane",
    forms:   "Form controls",
    buttons: "Buttons",
    flash:   "Flash messages"
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

  # CSS custom properties that are derived from the theme's text colour at render
  # time, mapped to their color-mix percentage.  Both to_css_properties (Ruby) and
  # the theme-designer Stimulus controller (JS, via a data attribute) read from
  # this single source so the formulas stay in sync.
  DERIVED_TEXT_PROPERTIES = {
    "tree-guide"                => 30,
    "avatar-placeholder-border" => 50
  }.freeze

  SWATCH_PROPERTIES = %w[page_bg pane_bg pane_title_text pane_link primary_button_bg].freeze

  # Returns the colour for a property, falling back to the default
  def color_for(property)
    colors&.dig(property.to_s) || THEMEABLE_PROPERTIES.dig(property.to_s, :default)
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
    text_color = color_for("pane_text")
    # --tree-guide and --avatar-placeholder-border are declared on :root as
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
    derived = DERIVED_TEXT_PROPERTIES.map { |css_prop, percent|
      "--#{css_prop}: color-mix(in srgb, #{text_color} #{percent}%, transparent);"
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
  CURRENT_EXPORT_VERSION = 2

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
      width, height = ImageDimensions.for(background_image.blob)
      return if width.nil?
      if width > BACKGROUND_IMAGE_MAX_DIMENSION || height > BACKGROUND_IMAGE_MAX_DIMENSION
        errors.add(:background_image, "must be #{BACKGROUND_IMAGE_MAX_DIMENSION}×#{BACKGROUND_IMAGE_MAX_DIMENSION} pixels or smaller")
      end
    end
end
