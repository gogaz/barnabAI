# frozen_string_literal: true

class Actions::StartPullRequestWorkflowAction < Actions::BaseAction
  include RepositoryResolverConcern

  def execute(parameters)
    pr_number = parameters[:pr_number] || parameters["pr_number"] || @pull_request&.number
    
    # Convert to integer if it's a string representation of a number
    pr_number = pr_number.to_i if pr_number && pr_number.to_s.match?(/^\d+$/)
    
    unless pr_number && pr_number > 0
      raise ArgumentError, "PR number is required"
    end

    # Get repository - either from @pull_request or find/create from parameters/context
    repository = if @pull_request
      @pull_request.repository
    elsif parameters[:repository]
      repo_name = parameters[:repository]
      # Disambiguate repository name if needed (handles both "owner/repo" and "repo-name" formats)
      disambiguated_repo = disambiguate_repository_for_user(repo_name)
      raise ArgumentError, "Repository '#{repo_name}' not found in your accessible repositories." unless disambiguated_repo
      find_or_create_repository(disambiguated_repo)
    else
      raise ArgumentError, "Repository information is required. Please specify the repository (e.g., 'owner/repo-name') or use this command in a PR thread."
    end

    # Get PR data to find the head branch
    pr_data = @github_service.get_pull_request(repository, pr_number)
    raise ArgumentError, "PR ##{pr_number} not found in #{repository.full_name}" unless pr_data

    head_branch = pr_data.head.ref

    # Try to find the latest failed workflow run for this branch
    workflow_runs = @github_service.get_workflow_runs(
      repository,
      branch: head_branch,
      per_page: 10
    )

    # Find the most recent failed run
    failed_run = workflow_runs.find { |run| run[:conclusion] == "failure" }

    if failed_run
      # Re-run failed jobs from the failed run
      @github_service.rerun_failed_workflow(repository, failed_run[:id])
      {
        success: true,
        message: "Re-running failed jobs from workflow run ##{failed_run[:id]} for PR ##{pr_number}",
        data: { run_id: failed_run[:id], workflow_name: failed_run[:name] }
      }
    else
      # No failed run found, trigger the workflow again on the branch
      # Try to find the workflow file (default to common CI workflow)
      workflow_file = parameters[:workflow_file] || ".github/workflows/ci.yml"
      
      @github_service.trigger_workflow(
        repository,
        workflow_file,
        ref: head_branch
      )
      
      {
        success: true,
        message: "Triggered workflow for PR ##{pr_number} on branch #{head_branch}",
        data: { branch: head_branch, workflow_file: workflow_file }
      }
    end
  rescue ArgumentError => e
    {
      success: false,
      message: e.message
    }
  rescue StandardError => e
    Rails.logger.error("Failed to start pull request workflow: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    {
      success: false,
      message: "Failed to start workflow: #{e.message}"
    }
  end
end
