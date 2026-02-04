class CreateSlackThreads < ActiveRecord::Migration[8.1]
  def change
    create_table :slack_threads do |t|
      t.references :pull_request, null: false, foreign_key: true
      t.string :slack_channel_id
      t.string :slack_thread_ts
      t.string :slack_user_id
      t.string :root_message_ts

      t.timestamps
    end
  end
end
