class CreateInclusionOverrides < ActiveRecord::Migration[8.1]
  def change
    create_table :inclusion_overrides do |t|
      t.references :group_group, null: false, foreign_key: { on_delete: :cascade }
      t.references :target_group, null: false, foreign_key: { to_table: :groups, on_delete: :cascade }
      t.string :inclusion_mode, null: false, default: "all"
      t.jsonb :included_subgroup_ids, null: false, default: []
      t.boolean :include_direct_profiles, null: false, default: true

      t.timestamps
    end

    add_index :inclusion_overrides, [ :group_group_id, :target_group_id ], unique: true
  end
end
