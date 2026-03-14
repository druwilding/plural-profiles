class AddCreditUrlToThemes < ActiveRecord::Migration[8.1]
  def change
    add_column :themes, :credit_url, :string, limit: 255
  end
end
