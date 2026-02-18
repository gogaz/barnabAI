# frozen_string_literal: true

class CreatePullRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :pull_requests do |t|
      t.string :repository_full_name, null: false
      t.integer :number, null: false
      t.string :github_pr_id
      t.string :title
      t.string :impacted_teams, array: true, default: []
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

    add_index :pull_requests, [:repository_full_name, :number], unique: true
    add_index :pull_requests, :state
  end
end
