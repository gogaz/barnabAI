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
        Rails.logger.info("✅ Using response from intent detection (saved 1 API call)")
        # Still log what the second prompt would have been for debugging
        log_chat_completion_prompt(user_message, context)
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
        pr_message = format_pr_message(pr)
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
      store_conversation(user_message, prs.first ? format_pr_message(prs.first) : response_message[:message], channel_id, thread_ts)
    else
      # Store conversation
      store_conversation(user_message, response_message, channel_id, thread_ts)

      # Send response to Slack
      # Only reply in a thread if the original message was in a thread
      # This ensures we maintain the same conversation level as the user
      # Check if response_message is JSON blocks (for pull_request_details_summary)
      message_options = {
        channel: channel_id
      }
      
      # Try to parse as JSON blocks, if it's valid JSON array, treat as blocks
      if response_message.is_a?(String) && response_message.strip.start_with?("[") && response_message.strip.end_with?("]")
        begin
          parsed_blocks = JSON.parse(response_message)
          if parsed_blocks.is_a?(Array)
            message_options[:blocks] = response_message
            # Determine fallback text based on intent or content
            fallback_text = if parsed_blocks.first&.dig("type") == "header" || parsed_blocks.any? { |b| b["type"] == "section" && b.dig("text", "text")&.include?("PR") }
              "PR Summary"
            else
              "Summary"
            end
            message_options[:text] = fallback_text
          else
            message_options[:text] = response_message
          end
        rescue JSON::ParserError
          # Not valid JSON, treat as plain text
          message_options[:text] = response_message
        end
      else
        message_options[:text] = response_message.is_a?(Hash) ? response_message[:message] : response_message
      end
      
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
    STDERR.puts "\n" + "=" * 80
    STDERR.puts "❌ NameError in ChatbotService: #{e.message}"
    STDERR.puts e.backtrace.join("\n")
    STDERR.puts "=" * 80 + "\n"
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

  def log_chat_completion_prompt(user_message, context)
    # Build and log the chat completion prompt even when using optimized response
    # This helps with debugging to see what the second prompt would have been
    messages = build_chat_messages(user_message, context)
    
    # Format messages exactly like GeminiProvider.format_messages_for_gemini does
    system_message = nil
    conversation_messages = []
    
    messages.each do |msg|
      role = msg[:role] || msg["role"]
      content = msg[:content] || msg["content"]
      
      if role == "system"
        system_message = content
      else
        conversation_messages << msg
      end
    end
    
    # Format conversation messages for Gemini (convert "assistant" to "model")
    contents = conversation_messages.map do |msg|
      role = msg[:role] || msg["role"]
      content = msg[:content] || msg["content"]
      gemini_role = role == "assistant" ? "model" : "user"
      
      {
        role: gemini_role,
        parts: [
          { text: content }
        ]
      }
    end
    
    # Prepend system message to first user message (Gemini format)
    if system_message && contents.any?
      first_message = contents.first
      if first_message[:role] == "user"
        first_message[:parts][0][:text] = "#{system_message}\n\n#{first_message[:parts][0][:text]}"
      end
    end
    
    # Log in the same format as GeminiProvider does
    puts "=" * 80
    puts "CHAT COMPLETION (SKIPPED - using optimized response)"
    puts "=" * 80
    
    request_body = {
      contents: contents,
      generationConfig: {
        temperature: 0.7,
        maxOutputTokens: 1000
      }
    }
    
    puts request_body.inspect
    puts "=" * 80
    puts "END CHAT COMPLETION (SKIPPED)"
    puts "=" * 80
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
        response = format_success_response(intent, result)
        # If response is an array (blocks), convert to JSON string for processing
        if response.is_a?(Array)
          response = response.to_json
        end
        response
      end
    else
      format_error_response(result)
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
    elsif intent == "list_prs_by_teams" && result[:data] && result[:data][:blocks]
      # Return blocks directly if available (AI-generated summary)
      return result[:data][:blocks]
    elsif intent == "list_prs_by_teams" && result[:data] && result[:data][:prs]
      # Fallback to text format if blocks not available
      prs = result[:data][:prs]
      teams = result[:data][:teams] || []
      message = "Found #{prs.count} PR(s) impacting team(s): #{teams.join(', ')}\n\n"
      prs.each do |pr|
        message += "• ##{pr[:number]}: #{pr[:title]} (#{pr[:state]})\n"
        message += "  Repository: #{pr[:repository]}\n"
        message += "  Impacted teams: #{pr[:impacted_teams]&.join(', ') || 'None'}\n"
        message += "  URL: #{pr[:url]}\n"
        message += "  Created: #{pr[:created_at]}\n\n"
      end
    end

    message
  end

  def format_error_response(result)
    result[:message] || "Failed to execute action."
  end

  def format_pr_message(pr)
    created_at = pr[:created_at]
    created_date = if created_at.respond_to?(:strftime)
      created_at.strftime("%Y-%m-%d")
    elsif created_at.is_a?(String)
      created_at
    else
      "unknown date"
    end
    
    # Format lines changed
    total_changes = pr[:total_changes] || (pr[:additions].to_i + pr[:deletions].to_i)
    lines_info = if total_changes > 0
      "+#{pr[:additions] || 0}/-#{pr[:deletions] || 0} (#{total_changes} total)"
    else
      "No changes"
    end
    
    pr_url = pr[:url] || "https://github.com/#{pr[:repository] || 'unknown/repo'}/pull/#{pr[:number]}"
    pr_title = pr[:title] || "PR ##{pr[:number]}"
    
    # Use Slack rich text format: title as link
    "<#{pr_url}|#{pr_title}>\n" \
    "Created: #{created_date} • Lines changed: #{lines_info}"
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
