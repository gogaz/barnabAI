# frozen_string_literal: true

class Actions::RunSpecsAction < Actions::BaseAction
  def execute(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    workflow_file = parameters[:workflow_file] || ".github/workflows/specs.yml"
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Pull request is required" unless @pull_request

    # Get the head branch for the workflow
    pr_data = @github_service.get_pull_request(@pull_request.repository, pr_number)
    ref = pr_data.head.ref

    result = @github_service.trigger_workflow(
      @pull_request.repository,
      workflow_file,
      ref: ref
    )

    {
      success: true,
      message: "Triggered specs workflow for PR ##{pr_number}",
      data: result
    }
  end
end
