class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :pull_request, null: false, foreign_key: true
      t.string :notification_type
      t.string :github_event_id
      t.text :payload
      t.boolean :processed
      t.datetime :processed_at

      t.timestamps
    end
  end
end
