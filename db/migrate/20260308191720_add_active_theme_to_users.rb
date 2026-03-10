class AddActiveThemeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :active_theme, null: true, foreign_key: { to_table: :themes }
  end
end
