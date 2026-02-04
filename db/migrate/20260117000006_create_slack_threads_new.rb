# frozen_string_literal: true

class CreateSlackThreadsNew < ActiveRecord::Migration[8.1]
  def change
    drop_table :slack_threads, if_exists: true
    
    create_table :slack_threads do |t|
      t.references :pull_request, null: false, foreign_key: true
      t.references :slack_installation, null: false, foreign_key: true
      t.string :slack_channel_id, null: false
      t.string :slack_thread_ts, null: false
      t.string :root_message_ts
      t.string :slack_user_id

      t.timestamps
    end

    add_index :slack_threads, [:slack_installation_id, :slack_channel_id, :slack_thread_ts], unique: true, name: "index_slack_threads_on_workspace_channel_thread"
  end
end
