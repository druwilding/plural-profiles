class AddMiniProfilePronounsToGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :mini_profile_pronouns, :string
    add_column :groups, :mini_profile_pronouns_inherited, :boolean, default: true, null: false
  end
end
