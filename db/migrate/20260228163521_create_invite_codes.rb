class CreateInviteCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :invite_codes do |t|
      t.string :code, null: false
      t.references :user, null: false, foreign_key: true
      t.bigint :redeemed_by_id
      t.datetime :redeemed_at

      t.timestamps
    end
    add_index :invite_codes, :code, unique: true
    add_foreign_key :invite_codes, :users, column: :redeemed_by_id
  end
end
