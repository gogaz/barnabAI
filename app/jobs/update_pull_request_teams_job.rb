# frozen_string_literal: true

class UpdatePullRequestTeamsJob < ApplicationJob
  queue_as :default

  def perform(repository_full_name, pr_number)
    user = User.joins(:github_tokens).order(:created_at).first
    unless user
      Rails.logger.warn('No user with GitHub token found, skipping UpdatePullRequestTeamsJob')
      return
    end

    pull_request = PullRequest.find_or_initialize_by(
      repository_full_name: repository_full_name,
      number: pr_number
    )

    github_service = Github::Client.new(user)

    if pull_request.new_record?
      github_pr = github_service.get_pull_request(repository_full_name, pr_number)
      return unless github_pr

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

    files = github_service.get_files(repository_full_name, pr_number)
    return unless files&.any?

    matcher = Github::CodeOwnersMatcher.new(github_service, repository_full_name)
    pull_request.impacted_teams = matcher.determine_impacted_teams(files)
    pull_request.save!
  rescue StandardError => e
    Rails.logger.error("Failed to update PR teams for #{repository_full_name}/#{pr_number}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise
  end
end
