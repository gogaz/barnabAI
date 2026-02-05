# frozen_string_literal: true

require "octokit"

class GithubService
  include GithubClientConcern

  def initialize(user)
    @user = user
  end

  # Delegate PR operations
  def get_pull_request(repository, pr_number)
    pr_operations.get_pull_request(repository, pr_number)
  end

  def list_pull_requests(repository, state: "open", limit: 10)
    pr_operations.list_pull_requests(repository, state: state, limit: limit)
  end

  def list_pull_requests_since(repository, since:, state: "all", limit: 100)
    pr_operations.list_pull_requests_since(repository, since: since, state: state, limit: limit)
  end

  def list_user_pull_requests(username, filters: {}, limit: 50)
    pr_operations.list_user_pull_requests(username, filters: filters, limit: limit)
  end

  def merge_pull_request(repository, pr_number, merge_method: "merge", commit_title: nil, commit_message: nil)
    pr_operations.merge_pull_request(repository, pr_number, merge_method: merge_method, commit_title: commit_title, commit_message: commit_message)
  end

  def create_comment(repository, pr_number, body)
    pr_operations.create_comment(repository, pr_number, body)
  end

  def get_comments(repository, pr_number)
    pr_operations.get_comments(repository, pr_number)
  end

  def get_review_comments(repository, pr_number)
    pr_operations.get_review_comments(repository, pr_number)
  end

  def get_reviews(repository, pr_number)
    pr_operations.get_reviews(repository, pr_number)
  end

  def get_check_runs(repository, pr_number)
    pr_operations.get_check_runs(repository, pr_number)
  end

  def get_files(repository, pr_number)
    pr_operations.get_files(repository, pr_number)
  end

  def create_pull_request(repository, title, head, base, body: nil)
    pr_operations.create_pull_request(repository, title, head, base, body: body)
  end

  def approve_pull_request(repository, pr_number, body: nil)
    pr_operations.approve_pull_request(repository, pr_number, body: body)
  end

  # Delegate workflow operations
  def trigger_workflow(repository, workflow_file, ref: "main")
    workflow_operations.trigger_workflow(repository, workflow_file, ref: ref)
  end

  def rerun_failed_workflow(repository, run_id)
    workflow_operations.rerun_failed_workflow(repository, run_id)
  end

  def get_workflow_runs(repository, branch: nil, workflow_id: nil, per_page: 10)
    workflow_operations.get_workflow_runs(repository, branch: branch, workflow_id: workflow_id, per_page: per_page)
  end

  # Delegate repository operations
  def get_file_content(repository, file_path, ref: nil)
    repository_operations.get_file_content(repository, file_path, ref: ref)
  end

  def list_user_repositories(limit: 100)
    repository_operations.list_user_repositories(limit: limit)
  end

  def disambiguate_repository(repo_name)
    repository_operations.disambiguate_repository(repo_name)
  end

  # Get repository info
  def get_repository(full_name)
    client.repository(full_name)
  end

  # Get user info
  def get_user_info
    client.user
  end

  private

  def client
    @client ||= github_client(@user)
  end

  def pr_operations
    @pr_operations ||= Github::PrOperations.new(client)
  end

  def workflow_operations
    @workflow_operations ||= Github::WorkflowOperations.new(client)
  end

  def repository_operations
    @repository_operations ||= Github::RepositoryOperations.new(client)
  end
end
