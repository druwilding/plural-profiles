class AddAvatarAltTextToProfilesAndGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :avatar_alt_text, :string
    add_column :groups, :avatar_alt_text, :string
  end
end
