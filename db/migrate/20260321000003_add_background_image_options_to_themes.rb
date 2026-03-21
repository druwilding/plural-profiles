class AddBackgroundImageOptionsToThemes < ActiveRecord::Migration[8.1]
  def change
    add_column :themes, :background_repeat, :string, default: "repeat", null: false
    add_column :themes, :background_size, :string, default: "auto", null: false
    add_column :themes, :background_position, :string, default: "center", null: false
    add_column :themes, :background_attachment, :string, default: "scroll", null: false
  end
end
