# frozen_string_literal: true

class Actions::RunWorkflowAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "run_workflow"
  function_description "Re-run a workflow or CI pipeline for a pull request. Use this when the user wants to retry failed checks."
  function_parameters({
    type: "object",
    properties: {
      workflow_id: {
        type: "integer",
        description: "Optional specific workflow run ID to re-run. If not provided, will re-run the most recent failed workflow."
      },
      rerun_failed_only: {
        type: "boolean",
        description: "If true, only re-run failed jobs. If false, re-run all jobs. Defaults to true."
      }
    }
  })

  def execute(parameters)
    pr_number = parameters[:pr_number] || parameters["pr_number"]
    repository = parameters[:repository] || parameters["repository"]
    workflow_id = parameters[:workflow_id] || parameters["workflow_id"]
    rerun_failed_only = parameters.fetch(:rerun_failed_only, parameters.fetch("rerun_failed_only", true))

    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Repository is required" unless repository

    # Get PR data to find the branch
    pr_data = github_client.get_pull_request(repository, pr_number)
    raise ArgumentError, "PR ##{pr_number} not found in #{repository}" unless pr_data

    if workflow_id
      # Re-run specific workflow
      if rerun_failed_only
        github_client.rerun_failed_workflow(repository, workflow_id)
        Slack::MessageBuilder.new(text: "Re-running failed jobs for workflow ##{workflow_id}")
      else
        github_client.rerun_workflow(repository, workflow_id)
        Slack::MessageBuilder.new(text: "Re-running all jobs for workflow ##{workflow_id}")
      end
    else
      # Find and re-run the most recent failed workflow
      workflow_runs = github_client.get_workflow_runs(
        repository,
        branch: pr_data.head.ref,
        per_page: 10
      )
      failed_run = workflow_runs.find { |run| run[:conclusion] == "failure" }

      if failed_run
        if rerun_failed_only
          github_client.rerun_failed_workflow(repository, failed_run[:id])
          Slack::MessageBuilder.new(text: "Re-running failed jobs from workflow ##{failed_run[:id]} for PR ##{pr_number}")
        else
          github_client.rerun_workflow(repository, failed_run[:id])
          Slack::MessageBuilder.new(text: "Re-running all jobs from workflow ##{failed_run[:id]} for PR ##{pr_number}")
        end
      else
        Slack::MessageBuilder.new(text: "No failed workflow found for PR ##{pr_number}. All workflows are passing or in progress.")
      end
    end
  end
end

