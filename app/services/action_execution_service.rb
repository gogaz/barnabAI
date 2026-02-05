# frozen_string_literal: true

class ActionExecutionService
  def initialize(user, pull_request: nil, slack_installation: nil)
    @user = user
    @pull_request = pull_request
    @slack_installation = slack_installation
    @github_service = GithubService.new(@user)
    @ai_provider = AIProviderFactory.create
  end

  def execute(intent, parameters)
    action_class = action_class_for(intent)
    return { success: false, message: "Unknown intent: #{intent}" } unless action_class

    action = action_class.new(
      @user,
      pull_request: @pull_request,
      slack_installation: @slack_installation,
      github_service: @github_service,
      ai_provider: @ai_provider
    )
    action.execute(parameters)
  rescue StandardError => e
    Rails.logger.error("Action execution failed: #{e.message}")
    { success: false, message: "Failed to execute action: #{e.message}" }
  end

  private

  def action_class_for(intent)
    case intent.to_s
    when "SUMMARIZE_EXISTING_PRS"
      Actions::SummarizeExistingPrsAction
    when "pull_request_details_summary"
      Actions::PullRequestDetailsSummaryAction
    when "merge_pr"
      Actions::MergePrAction
    when "comment_on_pr"
      Actions::CommentOnPrAction
    when "get_pr_info"
      Actions::GetPrInfoAction
    when "create_pr"
      Actions::CreatePrAction
    when "run_specs"
      Actions::RunSpecsAction
    when "start_pull_request_workflow"
      Actions::StartPullRequestWorkflowAction
    when "list_prs_by_teams"
      Actions::ListPrsByTeamsAction
    when "get_pr_files"
      Actions::GetPrFilesAction
    when "approve_pr"
      Actions::ApprovePrAction
    when "general_chat"
      nil # No action needed for general chat
    else
      nil
    end
  end
end
