class AddGithubOauthFieldsToRepositories < ActiveRecord::Migration[8.1]
  def change
    add_column :repositories, :github_user_id, :bigint
    add_column :repositories, :github_user_login, :string
    add_column :repositories, :github_oauth_connected_at, :datetime
    
    add_index :repositories, :github_user_id
  end
end
