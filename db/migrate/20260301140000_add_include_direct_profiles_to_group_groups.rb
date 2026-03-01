class AddIncludeDirectProfilesToGroupGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :group_groups, :include_direct_profiles, :boolean, default: true, null: false
  end
end
