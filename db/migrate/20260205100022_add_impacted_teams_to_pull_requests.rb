class AddImpactedTeamsToPullRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :pull_requests, :impacted_teams, :string, array: true, default: []
  end
end
