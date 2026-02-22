class AddUnverifiedEmailAddressToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :unverified_email_address, :string
  end
end
