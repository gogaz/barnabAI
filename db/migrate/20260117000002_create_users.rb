# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :slack_installation, null: false, foreign_key: true
      t.string :slack_user_id, null: false
      t.string :slack_username
      t.string :slack_display_name
      t.string :slack_email

      t.timestamps
    end

    add_index :users, [:slack_installation_id, :slack_user_id], unique: true
  end
end
