# frozen_string_literal: true

class ActionExecutionService
  def initialize(user, pull_request: nil)
    @user = user
    @pull_request = pull_request
    @github_service = GitHubService.new(@user)
  end

  def execute(intent, parameters)
    case intent.to_s
    when "merge_pr"
      execute_merge_pr(parameters)
    when "comment_on_pr"
      execute_comment_on_pr(parameters)
    when "get_pr_info"
      execute_get_pr_info(parameters)
    when "create_pr"
      execute_create_pr(parameters)
    when "run_specs"
      execute_run_specs(parameters)
    when "get_pr_files"
      execute_get_pr_files(parameters)
    when "approve_pr"
      execute_approve_pr(parameters)
    when "general_chat"
      { success: false, message: "This is a general chat message, no action needed." }
    else
      { success: false, message: "Unknown intent: #{intent}" }
    end
  rescue StandardError => e
    Rails.logger.error("Action execution failed: #{e.message}")
    { success: false, message: "Failed to execute action: #{e.message}" }
  end

  private

  def execute_merge_pr(parameters)
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

  def execute_comment_on_pr(parameters)
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

  def execute_get_pr_info(parameters)
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

  def execute_create_pr(parameters)
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

  def execute_run_specs(parameters)
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

  def execute_get_pr_files(parameters)
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

  def execute_approve_pr(parameters)
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

  def format_pr_info(pr_data)
    {
      number: pr_data.number,
      title: pr_data.title,
      state: pr_data.state,
      author: pr_data.user.login,
      head_branch: pr_data.head.ref,
      base_branch: pr_data.base.ref,
      created_at: pr_data.created_at,
      updated_at: pr_data.updated_at,
      merged_at: pr_data.merged_at,
      body: pr_data.body
    }
  end
end
