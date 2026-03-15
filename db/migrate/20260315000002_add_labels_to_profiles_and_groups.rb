class AddLabelsToProfilesAndGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :labels, :jsonb, default: [], null: false
    add_column :groups, :labels, :jsonb, default: [], null: false

    add_index :profiles, :labels, using: :gin, name: "index_profiles_on_labels"
    add_index :groups, :labels, using: :gin, name: "index_groups_on_labels"
  end
end
