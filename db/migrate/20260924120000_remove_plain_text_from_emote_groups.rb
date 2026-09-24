# Emotes now stand in as their name where they can't be images (page titles,
# confirm dialogs), so groups no longer need a symbol. Rolling back restores the
# column blank; the old symbols aren't kept.
class RemovePlainTextFromEmoteGroups < ActiveRecord::Migration[8.1]
  def change
    remove_column :emote_groups, :plain_text, :string, null: false, default: ""
  end
end
