class AddThemeToGroupsAndOverrideToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :groups, :theme, foreign_key: { on_delete: :nullify }, null: true
    add_column :users, :override_group_themes, :boolean, default: false, null: false
  end
end
