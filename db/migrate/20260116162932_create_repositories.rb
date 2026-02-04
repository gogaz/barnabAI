class CreateRepositories < ActiveRecord::Migration[8.1]
  def change
    create_table :repositories do |t|
      t.integer :github_repo_id
      t.string :name
      t.string :full_name
      t.string :owner
      t.string :webhook_secret
      t.text :access_token_encrypted

      t.timestamps
    end
  end
end
