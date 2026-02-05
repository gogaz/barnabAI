# frozen_string_literal: true

class ContextBuilderService
  def initialize(slack_installation, user, pull_request: nil, channel_id: nil, thread_ts: nil)
    @slack_installation = slack_installation
    @user = user
    @pull_request = pull_request
    @channel_id = channel_id
    @thread_ts = thread_ts
  end

  def build
    {
      workspace: build_workspace_context,
      user: build_user_context,
      pull_request: build_pr_context,
      conversation: build_conversation_context,
      thread_messages: build_thread_messages_context,
      user_mappings: build_user_mappings_context
    }
  end

  private

  def build_workspace_context
    {
      team_name: @slack_installation.team_name,
      team_id: @slack_installation.team_id
    }
  end

  def build_user_context
    {
      slack_user_id: @user.slack_user_id,
      slack_username: @user.slack_username,
      slack_display_name: @user.slack_display_name,
      has_github_token: @user.primary_github_token.present?,
      github_username: @user.primary_github_token&.github_username
    }
  end

  def build_pr_context
    return nil unless @pull_request

    github_service = GithubService.new(@user)
    pr_data = github_service.get_pull_request(@pull_request.repository, @pull_request.number)

    return nil unless pr_data

    # Fetch additional PR data
    comments = fetch_pr_comments(github_service)
    review_comments = fetch_review_comments(github_service)
    files = fetch_pr_files(github_service)

    {
      number: @pull_request.number,
      title: @pull_request.title || pr_data.title,
      body: @pull_request.body || pr_data.body,
      state: @pull_request.state || pr_data.state,
      author: @pull_request.author || pr_data.user.login,
      head_branch: @pull_request.head_branch || pr_data.head.ref,
      base_branch: @pull_request.base_branch || pr_data.base.ref,
      head_sha: @pull_request.head_sha || pr_data.head.sha,
      created_at: pr_data.created_at,
      updated_at: pr_data.updated_at,
      merged_at: pr_data.merged_at,
      repository: {
        full_name: @pull_request.repository.full_name,
        name: @pull_request.repository.name,
        owner: @pull_request.repository.owner
      },
      comments: format_comments(comments),
      review_comments: format_comments(review_comments),
      files: format_files(files)
    }
  rescue StandardError => e
    Rails.logger.error("Failed to build PR context: #{e.message}")
    {
      number: @pull_request.number,
      title: @pull_request.title,
      state: @pull_request.state,
      repository: {
        full_name: @pull_request.repository.full_name
      },
      error: "Failed to fetch full PR details"
    }
  end

  def build_conversation_context
    return [] unless @pull_request

    slack_thread = SlackThread.find_by(
      pull_request: @pull_request,
      slack_installation: @slack_installation
    )

    return [] unless slack_thread

    conversation = Conversation.find_by(
      user: @user,
      slack_thread: slack_thread
    )

    return [] unless conversation&.messages

    conversation.messages.map do |msg|
      {
        role: msg["role"] || msg[:role],
        content: msg["content"] || msg[:content],
        timestamp: msg["timestamp"] || msg[:timestamp]
      }
    end
  end

  def build_thread_messages_context
    # Fetch thread messages if thread_ts is present (works for both DMs and channels)
    # In DMs, if thread_ts is present, it means the user is in a thread
    return [] unless @thread_ts && @channel_id

    Rails.logger.info("Fetching thread messages for channel #{@channel_id}, thread #{@thread_ts}")
    
    messages = SlackService.get_thread_messages(
      @slack_installation,
      channel: @channel_id,
      thread_ts: @thread_ts
    )

    # Format messages for AI context
    messages.map do |msg|
      {
        user: msg[:user] || msg["user"],
        text: msg[:text] || msg["text"],
        timestamp: msg[:ts] || msg["ts"],
        is_bot: msg[:bot_id].present? || msg["bot_id"].present?
      }
    end
  rescue StandardError => e
    Rails.logger.error("Failed to build thread messages context: #{e.message}")
    []
  end

  def build_user_mappings_context
    mappings = UserMapping.where(slack_installation: @slack_installation)
    mappings.map do |mapping|
      {
        slack_user_id: mapping.slack_user_id,
        github_username: mapping.github_username,
        first_name: mapping.first_name
      }
    end
  end

  def fetch_pr_comments(github_service)
    return [] unless @pull_request

    github_service.get_comments(@pull_request.repository, @pull_request.number)
  rescue StandardError => e
    Rails.logger.error("Failed to fetch PR comments: #{e.message}")
    []
  end

  def fetch_review_comments(github_service)
    return [] unless @pull_request

    github_service.get_review_comments(@pull_request.repository, @pull_request.number)
  rescue StandardError => e
    Rails.logger.error("Failed to fetch review comments: #{e.message}")
    []
  end

  def fetch_pr_files(github_service)
    return [] unless @pull_request

    github_service.get_files(@pull_request.repository, @pull_request.number)
  rescue StandardError => e
    Rails.logger.error("Failed to fetch PR files: #{e.message}")
    []
  end

  def format_comments(comments)
    return [] unless comments

    comments.map do |comment|
      {
        author: comment.user&.login || comment.user&.name || "Unknown",
        body: comment.body,
        created_at: comment.created_at
      }
    end
  end

  def format_files(files)
    return [] unless files

    files.map do |file|
      {
        filename: file.filename,
        status: file.status,
        additions: file.additions,
        deletions: file.deletions,
        changes: file.changes
      }
    end
  end
end
