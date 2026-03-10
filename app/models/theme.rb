class Theme < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validate :colors_is_a_hash
  validate :colors_keys_are_known
  validate :colors_values_are_hex

  before_validation :normalize_colors_keys

  def colors=(value)
    super(value.is_a?(Hash) ? value.transform_keys(&:to_s) : value)
  end

  # The CSS custom properties that can be themed, mapped to their default values.
  # Properties that reference other variables (e.g. --heading: var(--text)) are
  # resolved to the concrete colour they point to so the colour picker always
  # starts with a hex value.
  THEMEABLE_PROPERTIES = {
    "page_bg"              => { label: "Page background",           default: "#0e2e24", group: :base },
    "pane_bg"              => { label: "Pane background",           default: "#133b2f", group: :base },
    "pane_border"          => { label: "Pane border",               default: "#02120e", group: :base },
    "heading"              => { label: "Headings",                  default: "#5ea389", group: :base },
    "text"                 => { label: "Text",                      default: "#5ea389", group: :base },
    "link"                 => { label: "Links",                     default: "#3ab580", group: :base },
    "spoiler"              => { label: "Spoiler background",        default: "#3A3A3A", group: :base },
    "primary_button_bg"    => { label: "Primary button background", default: "#11694a", group: :buttons },
    "primary_button_text"  => { label: "Primary button text",       default: "#58cc9d", group: :buttons },
    "secondary_button_text" => { label: "Secondary button text",    default: "#58cc9d", group: :buttons },
    "danger_button_bg"     => { label: "Danger button background",  default: "#a81d49", group: :buttons },
    "danger_button_text"   => { label: "Danger button text",        default: "#e6c4cf", group: :buttons },
    "input_label"          => { label: "Input labels",              default: "#5ea389", group: :forms },
    "input_bg"             => { label: "Input background",          default: "#263a2e", group: :forms },
    "input_border"         => { label: "Input border",              default: "#5ea389", group: :forms },
    "notice_bg"            => { label: "Notice background",         default: "#133b2f", group: :flash },
    "notice_border"        => { label: "Notice border",             default: "#5ea389", group: :flash },
    "notice_text"          => { label: "Notice text",               default: "#5ea389", group: :flash },
    "alert_bg"             => { label: "Alert background",          default: "#11694a", group: :flash },
    "alert_border"         => { label: "Alert border",              default: "#58cc9d", group: :flash },
    "alert_text"           => { label: "Alert text",                default: "#58cc9d", group: :flash },
    "warning_bg"           => { label: "Warning background",        default: "#a81d49", group: :flash },
    "warning_border"       => { label: "Warning border",            default: "#e6c4cf", group: :flash },
    "warning_text"         => { label: "Warning text",              default: "#e6c4cf", group: :flash }
  }.freeze

  PROPERTY_GROUPS = {
    base:    "Base colours",
    buttons: "Buttons",
    forms:   "Form controls",
    flash:   "Flash messages"
  }.freeze

  # Returns the colour for a property, falling back to the default
  def color_for(property)
    colors&.dig(property.to_s) || THEMEABLE_PROPERTIES.dig(property.to_s, :default)
  end

  # Generates a CSS string of custom property overrides
  def to_css_properties
    THEMEABLE_PROPERTIES.keys.filter_map { |prop|
      value = color_for(prop)
      css_prop = "--#{prop.tr('_', '-')}"
      "#{css_prop}: #{value};"
    }.join(" ")
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

  private

    HEX_COLOR_PATTERN = /\A#[0-9A-Fa-f]{6}\z/

    def normalize_colors_keys
      self.colors = colors.transform_keys(&:to_s) if colors.is_a?(Hash)
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
          errors.add(:colors, "value for '#{key}' is not a valid hex colour (expected #RRGGBB)")
        end
      end
    end
end
