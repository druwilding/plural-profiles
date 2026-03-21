class AddButtonBorderColorsToThemes < ActiveRecord::Migration[8.1]
  # Isolated model so the migration doesn't depend on the application Theme class.
  class Theme < ActiveRecord::Base
    self.table_name = "themes"
  end

  BORDER_DEFAULTS = {
    "primary_button_border"   => { from: "primary_button_text",   fallback: "#58cc9d" },
    "secondary_button_border" => { from: "secondary_button_text", fallback: "#58cc9d" },
    "danger_button_border"    => { from: "danger_button_text",    fallback: "#e6c4cf" }
  }.freeze

  def up
    Theme.find_each do |theme|
      colors = theme.colors || {}
      BORDER_DEFAULTS.each do |border_key, config|
        # Only set a default border color if it's missing or blank to keep existing custom values
        next if colors[border_key].present?
        colors[border_key] = colors[config[:from]] || config[:fallback]
      end
      theme.update_column(:colors, colors)
    end
  end

  def down
    Theme.find_each do |theme|
      colors = theme.colors || {}
      BORDER_DEFAULTS.each_key { |key| colors.delete(key) }
      theme.update_column(:colors, colors)
    end
  end
end
