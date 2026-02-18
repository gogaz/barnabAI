# frozen_string_literal: true

class ProcessGithubWebhookJob < ApplicationJob
  queue_as :default

  def perform(event_type:, delivery_id:, payload:)
    Rails.logger.info("Processing GitHub webhook: event=#{event_type}, delivery=#{delivery_id}")

    case event_type
    when "pull_request"
      handle_pull_request_event(payload)
    else
      Rails.logger.info("Ignoring unhandled GitHub event type: #{event_type}")
    end
  end

  private

  def handle_pull_request_event(payload)
    action = payload["action"]
    pr_data = payload["pull_request"]
    repo_data = payload["repository"]

    # Only handle merged pull requests for now
    return unless action == "closed" && pr_data["merged"]

    repository = find_repository(repo_data)
    return unless repository

    pull_request = create_or_update_pull_request(repository, pr_data)
    return unless pull_request

    UpdatePullRequestTeamsJob.perform_later(repository.id, pull_request.number)
  end

  def find_repository(repo_data)
    repository = Repository.find_by(github_repo_id: repo_data["id"])
    repository ||= Repository.find_by(full_name: repo_data["full_name"])

    unless repository
      Rails.logger.warn("Repository not found: #{repo_data['full_name']} (id: #{repo_data['id']})")
    end

    repository
  end

  def create_or_update_pull_request(repository, pr_data)
    pull_request = PullRequest.find_or_initialize_by(
      repository: repository,
      number: pr_data["number"]
    )

    pull_request.assign_attributes(
      github_pr_id: pr_data["id"].to_s,
      title: pr_data["title"],
      body: pr_data["body"],
      state: pr_data["state"],
      author: pr_data.dig("user", "login"),
      base_branch: pr_data.dig("base", "ref"),
      base_sha: pr_data.dig("base", "sha"),
      head_branch: pr_data.dig("head", "ref"),
      head_sha: pr_data.dig("head", "sha"),
      github_created_at: pr_data["created_at"],
      github_updated_at: pr_data["updated_at"],
      github_merged_at: pr_data["merged_at"]
    )

    if pull_request.save
      Rails.logger.info("Saved PR ##{pull_request.number} for #{repository.full_name}")
      pull_request
    else
      Rails.logger.error("Failed to save PR: #{pull_request.errors.full_messages.join(', ')}")
      nil
    end
  end
end

