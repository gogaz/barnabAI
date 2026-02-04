# frozen_string_literal: true

class CreateRepositoriesNew < ActiveRecord::Migration[8.1]
  def change
    # Drop dependent tables first to avoid foreign key constraints
    drop_table :notifications, if_exists: true
    drop_table :slack_threads, if_exists: true
    drop_table :pull_requests, if_exists: true
    drop_table :user_mappings, if_exists: true
    drop_table :repositories, if_exists: true
    
    create_table :repositories do |t|
      t.references :slack_installation, null: false, foreign_key: true
      t.string :full_name, null: false
      t.string :name, null: false
      t.string :owner, null: false
      t.integer :github_repo_id
      t.string :default_branch
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :repositories, [:slack_installation_id, :full_name], unique: true
    add_index :repositories, :github_repo_id
  end
end
