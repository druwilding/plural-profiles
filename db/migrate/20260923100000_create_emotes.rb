class CreateEmotes < ActiveRecord::Migration[8.1]
  def change
    create_table :emote_groups do |t|
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.string :plain_text, null: false
      # NULL owner = site-wide. Reserved for future server (Chat::Server) and
      # personal (User) emote groups.
      t.references :owner, polymorphic: true
      t.timestamps
    end
    # NULL owners never collide in a unique index, so site-wide group names are
    # kept unique by the model validation instead.
    add_index :emote_groups, [ :owner_type, :owner_id, :name ], unique: true

    create_table :emotes do |t|
      t.references :emote_group, null: false, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false
      t.boolean :code_overridden, null: false, default: false
      t.datetime :archived_at
      t.timestamps
    end
    # Site-wide only for now; these become per-scope once scoped emotes exist.
    add_index :emotes, :name, unique: true
    add_index :emotes, :code, unique: true

    create_table :emote_aliases do |t|
      t.references :emote, null: false, foreign_key: true
      t.string :code, null: false
      t.timestamps
    end
    add_index :emote_aliases, :code, unique: true
  end
end
