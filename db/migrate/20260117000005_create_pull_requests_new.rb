# frozen_string_literal: true

class CreatePullRequestsNew < ActiveRecord::Migration[8.1]
  def change
    drop_table :pull_requests, if_exists: true
    
    create_table :pull_requests do |t|
      t.references :repository, null: false, foreign_key: true
      t.integer :number, null: false
      t.integer :github_pr_id
      t.string :title
      t.text :body
      t.string :state
      t.string :author
      t.string :head_branch
      t.string :base_branch
      t.string :head_sha
      t.string :base_sha
      t.datetime :github_created_at
      t.datetime :github_updated_at
      t.datetime :github_merged_at

      t.timestamps
    end

    add_index :pull_requests, [:repository_id, :number], unique: true
    add_index :pull_requests, :github_pr_id
    add_index :pull_requests, :state
  end
end
