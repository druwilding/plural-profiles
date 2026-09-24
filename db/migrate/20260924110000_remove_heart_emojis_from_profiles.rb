# The picked-hearts arrays were replaced by the emotes text field
# (AddEmotesTextToProfiles), which has been in use since. Rolling back restores
# the columns empty; their old data isn't kept.
class RemoveHeartEmojisFromProfiles < ActiveRecord::Migration[8.1]
  def change
    remove_column :profiles, :heart_emojis, :jsonb, default: [], null: false
    remove_column :profiles, :mini_profile_heart_emojis, :jsonb, default: [], null: false
    remove_column :profiles, :mini_profile_heart_emojis_inherited, :boolean, default: true, null: false
  end
end
