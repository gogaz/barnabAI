# frozen_string_literal: true

class CreateUserMappingsNew < ActiveRecord::Migration[8.1]
  def change
    drop_table :user_mappings, if_exists: true
    
    create_table :user_mappings do |t|
      t.references :slack_installation, null: false, foreign_key: true
      t.string :slack_user_id, null: false
      t.string :github_username, null: false
      t.string :first_name

      t.timestamps
    end

    add_index :user_mappings, [:slack_installation_id, :slack_user_id, :github_username], unique: true, name: "index_user_mappings_unique"
  end
end
