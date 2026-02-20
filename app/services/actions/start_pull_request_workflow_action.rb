# frozen_string_literal: true

class Actions::StartPullRequestWorkflowAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "github_start_pull_request_workflow"
  function_description "Re-run a failed workflow for a pull request"
  function_parameters({
    type: "object",
    properties: {
      pr_number: {
        type: "integer",
        description: "The PR number from the list of messages. Can often be extracted from a URL or if the user mentions a PR number"
      },
      repository: {
        type: "string",
        description: "The Github repository full name including owner (ideal format: 'owner/repo-name'). Can often be extracted from a URL or if the user mentions a repository name."
      }
    },
    required: ["pr_number", "repository"]
  })

  def execute(parameters)
    number = parameters[:pr_number]

    raise ArgumentError, "PR number is required" if number.blank?

    repository = parameters[:repository]
    raise ArgumentError, "Please specify the repository (e.g., 'owner/repo-name')." if respository.blank?

    pr_data = github_client.get_pull_request(repository, number)
    raise ArgumentError, "PR ##{number} not found in #{repository}" unless pr_data

    workflow_runs = github_client.get_workflow_runs(
      repository,
      branch: pr_data.head.ref,
      per_page: 50
    )
    failed_run = workflow_runs.find { |run| run[:conclusion] == "failure" }

    if failed_run
      github_client.rerun_failed_workflow(repository, failed_run[:id])
      Slack::MessageBuilder.new(text: "Re-running failed jobs from workflow run ##{failed_run[:id]} for PR ##{number}")
    else
      Slack::MessageBuilder.new(text: "Test workflow for PR ##{number} is not currently failing. No workflow run was re-triggered.")
    end
  end
end
