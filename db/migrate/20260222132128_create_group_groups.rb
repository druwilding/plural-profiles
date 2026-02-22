class CreateGroupGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :group_groups do |t|
      t.references :parent_group, null: false, foreign_key: { to_table: :groups }
      t.references :child_group, null: false, foreign_key: { to_table: :groups }

      t.timestamps
    end
    add_index :group_groups, [ :parent_group_id, :child_group_id ], unique: true
  end
end
