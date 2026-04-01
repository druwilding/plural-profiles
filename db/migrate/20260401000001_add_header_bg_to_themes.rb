class AddHeaderBgToThemes < ActiveRecord::Migration[8.1]
  # Isolated model so the migration doesn't depend on the application Theme class.
  class Theme < ActiveRecord::Base
    self.table_name = "themes"
  end

  PANE_BG_DEFAULT = "#133b2f"

  def up
    Theme.find_each do |theme|
      colors = theme.colors || {}
      next if colors["header_bg"].present?

      colors["header_bg"] = colors["pane_bg"] || PANE_BG_DEFAULT
      theme.update_column(:colors, colors)
    end
  end

  def down
    Theme.find_each do |theme|
      colors = theme.colors || {}
      colors.delete("header_bg")
      theme.update_column(:colors, colors)
    end
  end
end
