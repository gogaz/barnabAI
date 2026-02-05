# frozen_string_literal: true

class Actions::GetPrInfoAction < Actions::BaseAction
  include PrFormatterConcern

  def execute(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Pull request is required" unless @pull_request

    pr_data = @github_service.get_pull_request(@pull_request.repository, pr_number)
    comments = @github_service.get_comments(@pull_request.repository, pr_number)
    files = @github_service.get_files(@pull_request.repository, pr_number)

    {
      success: true,
      message: "PR ##{pr_number} information",
      data: {
        pr: format_pr_info(pr_data),
        comments_count: comments&.count || 0,
        files_count: files&.count || 0,
        files: files&.map(&:filename) || []
      }
    }
  end
end
