class CreateGroupProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :group_profiles do |t|
      t.references :group, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true

      t.timestamps
    end
    add_index :group_profiles, [ :group_id, :profile_id ], unique: true
  end
end
