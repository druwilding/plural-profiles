class AddCreditAndNotesToThemes < ActiveRecord::Migration[8.1]
  def change
    add_column :themes, :credit, :string, limit: 255
    add_column :themes, :notes, :text
  end
end
