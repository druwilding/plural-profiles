class ChangeActiveThemeFkToNullify < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :users, column: :active_theme_id
    add_foreign_key :users, :themes, column: :active_theme_id, on_delete: :nullify
  end
end
