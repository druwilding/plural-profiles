class AddPronounsToGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :pronouns, :string
  end
end
