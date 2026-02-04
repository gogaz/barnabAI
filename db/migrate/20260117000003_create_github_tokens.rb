# frozen_string_literal: true

class CreateGithubTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :github_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.text :token_encrypted, null: false
      t.string :github_user_id
      t.string :github_username
      t.string :github_email
      t.string :scope
      t.datetime :connected_at

      t.timestamps
    end

    add_index :github_tokens, :github_user_id
  end
end
