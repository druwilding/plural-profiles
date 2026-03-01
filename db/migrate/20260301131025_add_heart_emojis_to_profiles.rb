class AddHeartEmojisToProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :heart_emojis, :jsonb, default: [], null: false
  end
end
