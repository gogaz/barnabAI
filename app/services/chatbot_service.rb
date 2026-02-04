# frozen_string_literal: true

class ChatbotService
  def initialize(slack_installation, user, pull_request: nil)
    @slack_installation = slack_installation
    @user = user
    @pull_request = pull_request
    @ai_provider = AIProviderFactory.create
    @intent_detection = IntentDetectionService.new(@ai_provider)
  end

  def process_message(user_message, channel_id:, thread_ts:)
    # Build context
    context = ::ContextBuilderService.new(@slack_installation, @user, pull_request: @pull_request).build

    # Detect intent
    intent_result = @intent_detection.detect_intent(user_message, context)

    # Execute action if not general chat
    response_message = if intent_result[:intent] == "general_chat"
      handle_general_chat(user_message, context)
    else
      handle_actionable_intent(intent_result, context)
    end

    # Store conversation
    store_conversation(user_message, response_message, channel_id, thread_ts)

    # Send response to Slack
    SlackService.send_message(
      @slack_installation,
      channel: channel_id,
      text: response_message,
      thread_ts: thread_ts
    )

    response_message
  rescue NameError => e
    # Re-raise NameError (uninitialized constant) to avoid silent failures
    Rails.logger.error("ChatbotService NameError: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    STDERR.puts "\n" + "=" * 80
    STDERR.puts "❌ NameError in ChatbotService: #{e.message}"
    STDERR.puts e.backtrace.join("\n")
    STDERR.puts "=" * 80 + "\n"
    raise
  rescue StandardError => e
    Rails.logger.error("ChatbotService error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    error_message = "Sorry, I encountered an error processing your request: #{e.message}"
    
    SlackService.send_message(
      @slack_installation,
      channel: channel_id,
      text: error_message,
      thread_ts: thread_ts
    )
    
    # Re-raise to avoid silent failures
    raise
  end

  private

  def handle_general_chat(user_message, context)
    # Use AI provider for general conversation
    messages = build_chat_messages(user_message, context)
    @ai_provider.chat_completion(messages)
  end

  def handle_actionable_intent(intent_result, context)
    intent = intent_result[:intent]
    parameters = intent_result[:parameters]

    # Check if user has GitHub token (using safe method)
    unless @user.has_github_token?
      return build_github_oauth_invitation_message
    end

    # Check if PR is required and available
    if requires_pr?(intent) && !@pull_request
      return "I need a PR context to perform this action. Please use this command in a PR thread."
    end

    # Execute the action
    action_service = ::ActionExecutionService.new(@user, pull_request: @pull_request)
    result = action_service.execute(intent, parameters)

    if result[:success]
      format_success_response(intent, result)
    else
      format_error_response(result)
    end
  end

  def requires_pr?(intent)
    %w[merge_pr comment_on_pr get_pr_info run_specs get_pr_files approve_pr].include?(intent.to_s)
  end

  def build_chat_messages(user_message, context)
    system_message = build_system_prompt(context)
    [
      { role: "system", content: system_message },
      { role: "user", content: user_message }
    ]
  end

  def build_system_prompt(context)
    pr_context = if context[:pull_request]
      pr = context[:pull_request]
      "You are helping with PR ##{pr[:number]}: #{pr[:title]}\n" \
      "Repository: #{pr[:repository][:full_name]}\n" \
      "State: #{pr[:state]}\n" \
      "Author: #{pr[:author]}\n"
    else
      "You are a helpful assistant for managing GitHub pull requests via Slack.\n"
    end

    "#{pr_context}\n" \
    "Answer questions helpfully and concisely. " \
    "If the user wants to perform an action, suggest the appropriate command."
  end

  def format_success_response(intent, result)
    message = result[:message] || "Action completed successfully."

    # Add additional details if available
    if result[:data] && intent == "get_pr_info"
      pr_data = result[:data][:pr]
      message += "\n\n" \
                 "PR ##{pr_data[:number]}: #{pr_data[:title]}\n" \
                 "State: #{pr_data[:state]}\n" \
                 "Author: #{pr_data[:author]}\n" \
                 "Comments: #{result[:data][:comments_count]}\n" \
                 "Files changed: #{result[:data][:files_count]}"
    end

    message
  end

  def format_error_response(result)
    result[:message] || "Failed to execute action."
  end

  def build_github_oauth_invitation_message
    # Generate OAuth URL with user context
    oauth_url = Rails.application.routes.url_helpers.github_oauth_authorize_url(
      slack_user_id: @user.slack_user_id,
      slack_installation_id: @slack_installation.id,
      host: ENV.fetch("APP_HOST", "localhost:3000"),
      protocol: ENV.fetch("APP_PROTOCOL", "http")
    )

    <<~MESSAGE
      👋 Hi! I need access to your GitHub account to help you with pull requests and repositories.

      To get started, please connect your GitHub account by clicking this link:
      #{oauth_url}

      Once connected, I'll be able to help you with:
      • Viewing and managing pull requests
      • Commenting on PRs
      • Merging pull requests
      • Running tests and workflows
      • And much more!

      Just click the link above to authorize the connection. 🔗
    MESSAGE
  end

  def store_conversation(user_message, assistant_message, channel_id, thread_ts)
    return unless @pull_request

    slack_thread = SlackThread.find_or_create_by!(
      pull_request: @pull_request,
      slack_installation: @slack_installation,
      slack_channel_id: channel_id,
      slack_thread_ts: thread_ts
    )

    conversation = Conversation.find_or_initialize_by(
      user: @user,
      slack_thread: slack_thread
    )

    messages = conversation.messages || []
    messages << {
      role: "user",
      content: user_message,
      timestamp: Time.current.iso8601
    }
    messages << {
      role: "assistant",
      content: assistant_message,
      timestamp: Time.current.iso8601
    }

    conversation.messages = messages
    conversation.save!
  end
end
