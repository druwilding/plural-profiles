class AddRelationshipTypeToGroupGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :group_groups, :relationship_type, :string, default: "nested", null: false
  end
end
