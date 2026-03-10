class CreateThemes < ActiveRecord::Migration[8.1]
  def change
    create_table :themes do |t|
      t.string :name, null: false
      t.references :user, null: false, foreign_key: true
      t.jsonb :colors, null: false, default: {}

      t.timestamps
    end
  end
end
