class CreateJournalDreamwidthConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :journal_dreamwidth_connections do |t|
      t.bigint :user_id, null: false
      t.string :username, null: false
      t.text :api_key, null: false
      t.string :api_key_digest, null: false
      t.datetime :verified_at
      t.datetime :failed_at
      t.jsonb :communities, default: [], null: false

      t.timestamps
    end

    # Both lead with user_id, so they also serve lookups by user alone.
    add_index :journal_dreamwidth_connections, [ :user_id, :username ], unique: true
    add_index :journal_dreamwidth_connections, [ :user_id, :api_key_digest ], unique: true

    add_foreign_key :journal_dreamwidth_connections, :users, column: :user_id
  end
end
