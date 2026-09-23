# Profiles' picked hearts become a plain emote text field, like pronouns, so
# people can repeat emotes and put them in any order. Each profile's picked
# hearts are copied over in order as codes, e.g. [dewdrop_heart, red_heart]
# becomes ":dewdrop_heart: :red_heart:". The same goes for the chat override.
#
# The old jsonb columns are left in place (Profile ignores them) so this can
# be rolled back; they're dropped once the new field has been in use a while.
class AddEmotesTextToProfiles < ActiveRecord::Migration[8.1]
  def up
    add_column :profiles, :emotes, :string
    add_column :profiles, :mini_profile_emotes, :string
    add_column :profiles, :mini_profile_emotes_inherited, :boolean, default: true, null: false

    execute <<~SQL.squish
      UPDATE profiles SET
        emotes = (
          SELECT string_agg(':' || code || ':', ' ' ORDER BY position)
          FROM jsonb_array_elements_text(heart_emojis) WITH ORDINALITY AS picked(code, position)
        ),
        mini_profile_emotes = (
          SELECT string_agg(':' || code || ':', ' ' ORDER BY position)
          FROM jsonb_array_elements_text(mini_profile_heart_emojis) WITH ORDINALITY AS picked(code, position)
        ),
        mini_profile_emotes_inherited = mini_profile_heart_emojis_inherited
    SQL
  end

  def down
    remove_column :profiles, :emotes
    remove_column :profiles, :mini_profile_emotes
    remove_column :profiles, :mini_profile_emotes_inherited
  end
end
