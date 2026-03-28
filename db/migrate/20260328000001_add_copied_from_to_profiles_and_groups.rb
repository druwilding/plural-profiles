class AddCopiedFromToProfilesAndGroups < ActiveRecord::Migration[8.1]
  def change
    add_reference :profiles, :copied_from, null: true, foreign_key: { to_table: :profiles }
    add_reference :groups, :copied_from, null: true, foreign_key: { to_table: :groups }
  end
end
