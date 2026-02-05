# frozen_string_literal: true

class Actions::CreatePrAction < Actions::BaseAction
  def execute(parameters)
    branch_name = parameters[:branch_name]
    base_branch = parameters[:base_branch] || "main"
    title = parameters[:title]
    raise ArgumentError, "Branch name is required" unless branch_name
    raise ArgumentError, "Title is required" unless title
    raise ArgumentError, "Pull request is required" unless @pull_request

    result = @github_service.create_pull_request(
      @pull_request.repository,
      title,
      branch_name,
      base_branch
    )

    {
      success: true,
      message: "Created PR ##{result.number}: #{title}",
      data: result
    }
  end
end
