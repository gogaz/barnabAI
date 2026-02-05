# frozen_string_literal: true

class Actions::ApprovePrAction < Actions::BaseAction
  def execute(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    body = parameters[:message] || "Approved via Slack bot"
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Pull request is required" unless @pull_request

    result = @github_service.approve_pull_request(
      @pull_request.repository,
      pr_number,
      body: body
    )

    {
      success: true,
      message: "Approved PR ##{pr_number}",
      data: result
    }
  end
end
