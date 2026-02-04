# frozen_string_literal: true

class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    drop_table :conversations, if_exists: true
    
    create_table :conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :slack_thread, null: true, foreign_key: true
      t.jsonb :messages, default: [], null: false

      t.timestamps
    end

    # Index is automatically created by t.references above
  end
end
