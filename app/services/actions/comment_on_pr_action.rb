# frozen_string_literal: true

class Actions::CommentOnPrAction < Actions::BaseAction
  def execute(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    message = parameters[:message]
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Message is required" unless message
    raise ArgumentError, "Pull request is required" unless @pull_request

    result = @github_service.create_comment(
      @pull_request.repository,
      pr_number,
      message
    )

    {
      success: true,
      message: "Comment posted on PR ##{pr_number}",
      data: result
    }
  end
end
