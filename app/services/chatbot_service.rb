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
    # Pass channel_id and thread_ts to fetch thread messages if in a thread
    # For DMs, thread_ts will be nil, so no thread context will be fetched
    context = ::ContextBuilderService.new(
      @slack_installation,
      @user,
      pull_request: @pull_request,
      channel_id: channel_id,
      thread_ts: thread_ts
    ).build

    # Detect intent
    intent_result = @intent_detection.detect_intent(user_message, context)

    # Handle different intent types
    response_message = case intent_result[:intent]
    when "general_chat"
      # Use response from intent detection if available (saves an API call)
      response = intent_result[:parameters][:response] || intent_result[:parameters]["response"]
      if response.present?
        response
      else
      handle_general_chat(user_message, context)
      end
    when "ask_clarification"
      handle_clarification_request(intent_result)
    else
      handle_actionable_intent(intent_result, context)
    end

    # Handle multiple messages for SUMMARIZE_EXISTING_PRS
    if intent_result[:intent] == "SUMMARIZE_EXISTING_PRS" && response_message.is_a?(Hash) && response_message[:multiple_messages]
      # Send one message per PR
      prs = response_message[:prs] || []
      prs.each do |pr|
        pr_message = Formatters::PrMessageFormatter.format(pr)
        message_options = {
          channel: channel_id,
          text: pr_message
        }
        message_options[:thread_ts] = thread_ts if thread_ts
        
        SlackService.send_message(
          @slack_installation,
          **message_options
        )
      end
      
      # Store conversation with the first PR message as the assistant message
      store_conversation(user_message, prs.first ? Formatters::PrMessageFormatter.format(prs.first) : response_message[:message], channel_id, thread_ts)
    else
    # Store conversation
    store_conversation(user_message, response_message, channel_id, thread_ts)

    # Send response to Slack
    # Only reply in a thread if the original message was in a thread
    # This ensures we maintain the same conversation level as the user
    message_options = Formatters::SlackMessageFormatter.format_message_options(response_message)
    message_options[:channel] = channel_id
    message_options[:thread_ts] = thread_ts if thread_ts

    SlackService.send_message(
      @slack_installation,
      **message_options
    )
    end

    response_message
  rescue NameError => e
    # Re-raise NameError (uninitialized constant) to avoid silent failures
    Rails.logger.error("ChatbotService NameError: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise
  rescue StandardError => e
    Rails.logger.error("ChatbotService error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    error_message = "Sorry, I encountered an error processing your request: #{e.message}"
    
    # Only reply in a thread if the original message was in a thread
    message_options = {
      channel: channel_id,
      text: error_message
    }
    message_options[:thread_ts] = thread_ts if thread_ts
    
    SlackService.send_message(
      @slack_installation,
      **message_options
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


  def handle_clarification_request(intent_result)
    # Return the clarification question from the intent detection
    question = intent_result[:parameters][:clarification_question] || 
               intent_result[:parameters]["clarification_question"] ||
               "Could you please clarify what you'd like me to do?"
    
    question
  end

  def handle_actionable_intent(intent_result, context)
    intent = intent_result[:intent]
    parameters = intent_result[:parameters]

    # Check if user has GitHub token (using safe method)
    unless @user.has_github_token?
      return build_github_oauth_invitation_message
    end

    # Check if PR is required and available
    # Some intents can work with PR info from parameters/context even without @pull_request
    # (e.g., pull_request_details_summary, start_pull_request_workflow, list_prs_by_teams)
    if requires_pr?(intent) && !@pull_request && intent != "SUMMARIZE_EXISTING_PRS" && 
       intent != "pull_request_details_summary" && intent != "start_pull_request_workflow" &&
       intent != "list_prs_by_teams"
      return "I need a PR context to perform this action. Please use this command in a PR thread."
    end

    # Execute the action
    action_service = ::ActionExecutionService.new(@user, pull_request: @pull_request, slack_installation: @slack_installation)
    result = action_service.execute(intent, parameters)

    if result[:success]
      # Special handling for SUMMARIZE_EXISTING_PRS - return data for multiple messages
      if intent == "SUMMARIZE_EXISTING_PRS" && result[:data] && result[:data][:multiple_messages]
        {
          multiple_messages: true,
          prs: result[:data][:prs] || [],
          message: result[:message] || "Found pull requests"
        }
      else
        response = Formatters::ResponseFormatter.format_success(intent, result)
        # If response is an array (blocks), convert to JSON string for processing
        if response.is_a?(Array)
          response = response.to_json
        end
        response
      end
    else
      Formatters::ResponseFormatter.format_error(result)
    end
  end

  def requires_pr?(intent)
    %w[merge_pr comment_on_pr get_pr_info run_specs start_pull_request_workflow get_pr_files approve_pr].include?(intent.to_s)
  end

  def build_chat_messages(user_message, context)
    system_message = build_system_prompt(context)
    messages = [{ role: "system", content: system_message }]

    # Add thread messages as context if available (only in threads, not DMs)
    thread_messages = context[:thread_messages] || []
    if thread_messages.any?
      Rails.logger.info("Including #{thread_messages.count} thread messages in context")
      
      # Get the bot user ID to identify bot messages
      bot_user_id = @slack_installation.bot_user_id rescue nil
      
      # Add thread messages as user/assistant messages for context
      # Exclude the current message (it will be added at the end)
      thread_messages.each do |thread_msg|
        msg_text = thread_msg[:text] || thread_msg["text"]
        msg_user = thread_msg[:user] || thread_msg["user"]
        is_bot = thread_msg[:is_bot] || thread_msg["is_bot"] || false
        
        # Skip if empty or if it's a bot message (unless we want to include our own bot messages)
        next if msg_text.blank?
        
        # Determine role:
        # - If it's from the current user, it's "user"
        # - If it's from the bot, it's "assistant"
        # - Otherwise, it's another user, treat as "user" for context
        role = if is_bot || msg_user == bot_user_id
          "assistant"
        else
          "user"
        end
        
        messages << {
          role: role,
          content: msg_text
        }
      end
    end

    # Add the current user message
    messages << { role: "user", content: user_message }

    messages
  end

  def build_system_prompt(context)
    pr_context = if context[:pull_request]
      pr = context[:pull_request]
      "You are helping with PR ##{pr[:number]}: #{pr[:title]}\n" \
      "Repository: #{pr[:repository][:full_name]}\n" \
      "State: #{pr[:state]}\n" \
      "Author: #{pr[:author]}\n"
    else
      ""
    end

    thread_context = if context[:thread_messages]&.any?
      "You are in a Slack thread with previous messages. Use the conversation history to understand the context.\n"
    else
      ""
    end

    "#{pr_context}\n#{thread_context}\n" \
    "Answer questions helpfully and concisely. " \
    "If the user wants to perform an action, suggest the appropriate command."
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
    # For PR threads: store with slack_thread
    if @pull_request
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
    else
      # For direct messages (DMs): store without slack_thread
      # Only store if we're not in a thread (thread_ts is nil)
      return if thread_ts

      conversation = Conversation.find_or_initialize_by(
        user: @user,
        slack_thread: nil
      )
    end

    messages = conversation.messages || []
    messages << {
      role: "user",
      content: user_message,
      timestamp: Time.current.iso8601
    }
    
    # Extract text from blocks if assistant_message is JSON blocks
    assistant_text = extract_text_from_blocks(assistant_message)
    messages << {
      role: "assistant",
      content: assistant_text,
      timestamp: Time.current.iso8601
    }

    conversation.messages = messages
    conversation.save!
  end

  def extract_text_from_blocks(message)
    # If message is JSON blocks, extract text content from them
    return message unless message.is_a?(String)
    
    # Check if it's JSON blocks (starts with [ and ends with ])
    if message.strip.start_with?("[") && message.strip.end_with?("]")
      begin
        blocks = JSON.parse(message)
        return message unless blocks.is_a?(Array)
        
        # Extract text from all text-containing blocks
        text_parts = []
        blocks.each do |block|
          case block["type"]
          when "section"
            if block["text"]
              text_parts << extract_text_from_block_element(block["text"])
            end
            if block["fields"]
              block["fields"].each do |field|
                text_parts << extract_text_from_block_element(field)
              end
            end
          when "header"
            text_parts << extract_text_from_block_element(block["text"])
          when "context"
            if block["elements"]
              block["elements"].each do |element|
                text_parts << extract_text_from_block_element(element)
              end
            end
          when "divider"
            # No text in dividers
          else
            # For other block types, try to find text field
            if block["text"]
              text_parts << extract_text_from_block_element(block["text"])
            end
          end
        end
        
        # Return extracted text or fallback to original if nothing found
        extracted = text_parts.compact.join("\n").strip
        extracted.present? ? extracted : message
      rescue JSON::ParserError
        # Not valid JSON, return as-is
        message
      end
    else
      message
    end
  end

  def extract_text_from_block_element(element)
    return nil unless element
    
    if element.is_a?(Hash)
      element["text"] || element[:text] || ""
    else
      element.to_s
    end
  end
end
