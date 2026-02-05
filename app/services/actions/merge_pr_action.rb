# frozen_string_literal: true

class Actions::MergePrAction < Actions::BaseAction
  def execute(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Pull request is required" unless @pull_request

    result = @github_service.merge_pull_request(
      @pull_request.repository,
      pr_number
    )

    {
      success: true,
      message: "Successfully merged PR ##{pr_number}",
      data: result
    }
  end
end
