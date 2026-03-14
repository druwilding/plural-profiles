class AddTagsToThemes < ActiveRecord::Migration[8.1]
  def change
    add_column :themes, :tags, :string, array: true, default: [], null: false
    add_index :themes, :tags, using: :gin
  end
end
