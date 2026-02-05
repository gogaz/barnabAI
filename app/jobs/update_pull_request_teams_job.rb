# frozen_string_literal: true

class UpdatePullRequestTeamsJob < ApplicationJob
  queue_as :default

  def perform(repository_id, pr_number)
    repository = Repository.find_by(id: repository_id)
    return unless repository

    # Find or create the PR record
    pull_request = PullRequest.find_or_initialize_by(
      repository: repository,
      number: pr_number
    )

    # If PR doesn't exist in our DB yet, we need to fetch basic info from GitHub
    if pull_request.new_record?
      user = repository.slack_installation.users.first
      return unless user

      github_service = GithubService.new(user)
      github_pr = github_service.get_pull_request(repository, pr_number)
      return unless github_pr

      # Set basic PR attributes
      pull_request.assign_attributes(
        github_pr_id: github_pr.id,
        title: github_pr.title,
        body: github_pr.body,
        state: github_pr.state,
        author: github_pr.user&.login,
        base_branch: github_pr.base&.ref,
        base_sha: github_pr.base&.sha,
        head_branch: github_pr.head&.ref,
        head_sha: github_pr.head&.sha,
        github_created_at: github_pr.created_at,
        github_updated_at: github_pr.updated_at,
        github_merged_at: github_pr.merged_at
      )
    end

    # Get the user for GitHub API access
    user = repository.slack_installation.users.first
    return unless user

    github_service = GithubService.new(user)

    # Fetch files changed in the PR
    files = github_service.get_files(repository, pr_number)
    return unless files&.any?

    # Determine impacted teams using CodeownersMatcher
    matcher = CodeownersMatcher.new(github_service, repository)
    impacted_teams = matcher.determine_impacted_teams(files)

    # Update the PR with impacted teams
    pull_request.impacted_teams = impacted_teams
    puts pull_request.inspect
    pull_request.save!
  rescue StandardError => e
    Rails.logger.error("Failed to update PR teams for #{repository_id}/#{pr_number}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise
  end
end
