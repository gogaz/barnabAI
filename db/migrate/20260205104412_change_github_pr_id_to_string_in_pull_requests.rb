class ChangeGithubPrIdToStringInPullRequests < ActiveRecord::Migration[8.1]
  def change
    change_column :pull_requests, :github_pr_id, :string
  end
end
