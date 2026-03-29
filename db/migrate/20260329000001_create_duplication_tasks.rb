class CreateDuplicationTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :duplication_tasks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :group, null: false, foreign_key: true
      t.jsonb :avatar_mappings, null: false, default: {}
      t.integer :total_avatars, null: false, default: 0
      t.integer :copied_avatars, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.timestamps
    end
  end
end
