# frozen_string_literal: true

class CreateUserMappings < ActiveRecord::Migration[8.1]
  def change
    drop_table :user_mappings, if_exists: true
    
    create_table :user_mappings do |t|
      t.references :user
      t.string :slack_user_id, null: false
      t.string :github_username, null: false
      t.string :slack_username, null: false

      t.timestamps
    end

    add_index :user_mappings, [:slack_user_id, :github_username], unique: true, name: "index_user_mappings_unique"
    add_index :user_mappings, [:user_id, :slack_user_id], unique: true, name: "index_user_mappings_on_user_id_and_slack_user_id"
  end
end
