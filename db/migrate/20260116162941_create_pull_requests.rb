class CreatePullRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :pull_requests do |t|
      t.references :repository, null: false, foreign_key: true
      t.integer :github_pr_id
      t.integer :number
      t.string :title
      t.string :author
      t.string :state
      t.string :head_sha
      t.string :base_branch
      t.string :head_branch

      t.timestamps
    end
  end
end
