class AddLabelsToProfilesAndGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :labels, :jsonb, default: [], null: false
    add_column :groups, :labels, :jsonb, default: [], null: false
  end
end
