# frozen_string_literal: true

require "octokit"

class GitHubService
  def initialize(user)
    @user = user
    @client = create_client
  end

  # Get a specific PR
  def get_pull_request(repository, pr_number)
    @client.pull_request(repository.full_name, pr_number)
  rescue Octokit::NotFound
    nil
  end

  # List PRs for a repository
  def list_pull_requests(repository, state: "open", limit: 10)
    @client.pull_requests(repository.full_name, state: state, per_page: limit)
  end

  # Merge a PR
  def merge_pull_request(repository, pr_number, merge_method: "merge", commit_title: nil, commit_message: nil)
    options = { merge_method: merge_method }
    options[:commit_title] = commit_title if commit_title
    options[:commit_message] = commit_message if commit_message

    @client.merge_pull_request(repository.full_name, pr_number, options)
  end

  # Create a comment on a PR
  def create_comment(repository, pr_number, body)
    @client.add_comment(repository.full_name, pr_number, body)
  end

  # Get comments on a PR
  def get_comments(repository, pr_number)
    @client.issue_comments(repository.full_name, pr_number)
  end

  # Get review comments on a PR
  def get_review_comments(repository, pr_number)
    @client.pull_request_comments(repository.full_name, pr_number)
  end

  # Get files changed in a PR
  def get_files(repository, pr_number)
    @client.pull_request_files(repository.full_name, pr_number)
  end

  # Create a PR
  def create_pull_request(repository, title, head, base, body: nil)
    @client.create_pull_request(
      repository.full_name,
      base,
      head,
      title,
      body
    )
  end

  # Approve a PR
  def approve_pull_request(repository, pr_number, body: nil)
    @client.create_pull_request_review(
      repository.full_name,
      pr_number,
      event: "APPROVE",
      body: body
    )
  end

  # Trigger a workflow (run specs)
  def trigger_workflow(repository, workflow_file, ref: "main")
    # This requires the workflow_dispatch event
    # Note: This is a simplified version - you may need to adjust based on your CI setup
    @client.post(
      "/repos/#{repository.full_name}/actions/workflows/#{workflow_file}/dispatches",
      { ref: ref }
    )
  end

  # Get repository info
  def get_repository(full_name)
    @client.repository(full_name)
  end

  # Get user info
  def get_user_info
    @client.user
  end

  private

  def create_client
    github_token = @user.primary_github_token
    raise ArgumentError, "User has no GitHub token connected" unless github_token

    token = github_token.token
    raise ArgumentError, "GitHub token is invalid or expired" unless token

    Octokit::Client.new(access_token: token)
  end
end
