# Emote groups are now emote sets. Renaming the table and column renames their
# conventionally named indexes too, and the foreign key follows the table. The
# polymorphic owner index is named after "owner" rather than its columns, so
# Rails leaves it alone and it's renamed here.
class RenameEmoteGroupsToEmoteSets < ActiveRecord::Migration[8.1]
  def change
    rename_table :emote_groups, :emote_sets
    rename_index :emote_sets, :index_emote_groups_on_owner, :index_emote_sets_on_owner
    rename_column :emotes, :emote_group_id, :emote_set_id
  end
end
