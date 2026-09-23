# Groups get the same emotes text field as profiles, shown next to their
# pronouns, with its own chat override.
class AddEmotesToGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :emotes, :string
    add_column :groups, :mini_profile_emotes, :string
    add_column :groups, :mini_profile_emotes_inherited, :boolean, default: true, null: false
  end
end
