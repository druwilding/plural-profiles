class AddInclusionToGroupGroups < ActiveRecord::Migration[8.1]
  def up
    add_column :group_groups, :inclusion_mode, :string, null: false, default: "all"
    add_column :group_groups, :included_subgroup_ids, :jsonb, null: false, default: []

    # Translate existing values: nested -> all, overlapping -> none
    execute <<-SQL.squish
      UPDATE group_groups
      SET inclusion_mode = CASE
        WHEN relationship_type = 'nested' THEN 'all'
        WHEN relationship_type = 'overlapping' THEN 'none'
        ELSE 'none'
      END
      WHERE relationship_type IS NOT NULL
    SQL

    # Remove the old column now that we've migrated values
    remove_column :group_groups, :relationship_type
  end

  def down
    # Recreate the old column and translate values back
    add_column :group_groups, :relationship_type, :string, null: false, default: 'nested'

    execute <<-SQL.squish
      UPDATE group_groups
      SET relationship_type = CASE
        WHEN inclusion_mode = 'all' THEN 'nested'
        WHEN inclusion_mode = 'none' THEN 'overlapping'
        ELSE 'overlapping'
      END
      WHERE inclusion_mode IS NOT NULL
    SQL

    remove_column :group_groups, :included_subgroup_ids
    remove_column :group_groups, :inclusion_mode
  end
end
