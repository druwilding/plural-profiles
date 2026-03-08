class RemoveInclusionModesFromGroupGroups < ActiveRecord::Migration[8.1]
  def change
    remove_column :group_groups, :subgroup_inclusion_mode, :string, default: "all", null: false
    remove_column :group_groups, :included_subgroup_ids, :jsonb, default: [], null: false
    remove_column :group_groups, :profile_inclusion_mode, :string, default: "all", null: false
    remove_column :group_groups, :included_profile_ids, :jsonb, default: [], null: false
  end
end
