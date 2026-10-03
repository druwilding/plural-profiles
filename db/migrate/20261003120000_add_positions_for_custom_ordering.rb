# Custom ordering: each list's order lives on the table that defines
# membership of that list. NULL means "not positioned", so untouched lists
# keep their alphabetical order and nothing needs backfilling.
class AddPositionsForCustomOrdering < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :position, :integer
    add_column :profiles, :position, :integer
    add_column :group_profiles, :position, :integer
    add_column :group_groups, :position, :integer

    add_index :group_profiles, [ :group_id, :position ]
    add_index :group_groups, [ :parent_group_id, :position ]
  end
end
