class RenameOverrideGroupThemesToOverrideThemes < ActiveRecord::Migration[7.0]
  def change
    rename_column :users, :override_group_themes, :override_themes
  end
end
