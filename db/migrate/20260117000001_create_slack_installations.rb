# frozen_string_literal: true

class CreateSlackInstallations < ActiveRecord::Migration[8.1]
  def change
    create_table :slack_installations do |t|
      t.string :team_id, null: false, index: { unique: true }
      t.string :team_name
      t.text :bot_token_encrypted, null: false
      t.text :access_token_encrypted
      t.string :bot_user_id
      t.string :bot_scope
      t.string :installing_user_id
      t.datetime :installed_at

      t.timestamps
    end
  end
end
