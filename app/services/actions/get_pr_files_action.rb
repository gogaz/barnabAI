# frozen_string_literal: true

class Actions::GetPrFilesAction < Actions::BaseAction
  def execute(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Pull request is required" unless @pull_request

    files = @github_service.get_files(@pull_request.repository, pr_number)

    {
      success: true,
      message: "Files changed in PR ##{pr_number}",
      data: {
        files: files.map do |file|
          {
            filename: file.filename,
            status: file.status,
            additions: file.additions,
            deletions: file.deletions,
            changes: file.changes
          }
        end
      }
    }
  end
end
