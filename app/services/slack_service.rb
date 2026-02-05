# frozen_string_literal: true

require "slack-ruby-client"
require "faye/websocket"
require "eventmachine"
require "json"
require "net/http"
require "uri"

class SlackService
  class << self
    # Start Slack Socket Mode connection
    # This creates a single global connection that handles events for all workspaces
    # Following official Slack documentation: https://docs.slack.dev/apis/events-api/using-socket-mode/#implementing
    def start_socket_mode
      return if @socket_mode_running

      app_token = ENV.fetch("SLACK_APP_TOKEN") do
        raise "SLACK_APP_TOKEN environment variable is required for Socket Mode"
      end

      # Validate token format and provide helpful error messages
      if app_token.blank?
        raise "SLACK_APP_TOKEN is empty. Please set it in your environment variables."
      end

      unless app_token.start_with?("xapp-")
        error_msg = "SLACK_APP_TOKEN doesn't start with 'xapp-'. "
        if app_token.start_with?("xoxb-")
          error_msg += "You're using a bot token (xoxb-), but Socket Mode requires an app-level token (xapp-). "
        elsif app_token.start_with?("xoxp-")
          error_msg += "You're using a user token (xoxp-), but Socket Mode requires an app-level token (xapp-). "
        end
        error_msg += "Get an app-level token from: https://api.slack.com/apps -> Your App -> Socket Mode -> App-Level Tokens"
        Rails.logger.error(error_msg)
        raise error_msg
      end

      Rails.logger.info("Starting Slack Socket Mode connection with token: #{app_token[0..14]}...")
      Rails.logger.info("Token length: #{app_token.length} characters")

      @socket_mode_running = true
      @app_token = app_token

      # Start WebSocket connection in a separate thread
      Thread.new do
        EventMachine.run do
          connect_socket_mode
        end
      end

      Rails.logger.info("Slack Socket Mode connection thread started")
    rescue StandardError => e
      Rails.logger.error("Failed to start Slack Socket Mode: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      @socket_mode_running = false
      raise
    end

    # Send a message to a Slack channel
    # Supports both plain text and Slack Block Kit blocks
    def send_message(slack_installation, channel:, text: nil, blocks: nil, thread_ts: nil)
      bot_token = slack_installation.bot_token
      raise "Bot token not available for installation #{slack_installation.team_id}" unless bot_token

      client = Slack::Web::Client.new(token: bot_token)

      options = {
        channel: channel
      }
      
      # If blocks are provided, use them; otherwise use text
      if blocks
        # Parse blocks if it's a JSON string, otherwise use as-is
        parsed_blocks = if blocks.is_a?(String)
          JSON.parse(blocks)
        else
          blocks
        end
        options[:blocks] = parsed_blocks
        # Fallback text for notifications (required by Slack)
        options[:text] = text || "PR Summary"
      else
        options[:text] = text
      end
      
      options[:thread_ts] = thread_ts if thread_ts

      response = client.chat_postMessage(options)

      if response["ok"]
        Rails.logger.info("Message sent to Slack channel #{channel}")
        response
      else
        error = response["error"] || "Unknown error"
        Rails.logger.error("Failed to send Slack message: #{error}")
        raise "Failed to send Slack message: #{error}"
      end
    rescue StandardError => e
      Rails.logger.error("Error sending Slack message: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise
    end

    # Add a reaction to a Slack message
    def add_reaction(slack_installation, channel:, timestamp:, name:)
      bot_token = slack_installation.bot_token
      raise "Bot token not available for installation #{slack_installation.team_id}" unless bot_token

      client = Slack::Web::Client.new(token: bot_token)

      response = client.reactions_add(
        channel: channel,
        timestamp: timestamp,
        name: name
      )

      if response["ok"]
        Rails.logger.info("Reaction :#{name}: added to message #{timestamp}")
        response
      else
        error = response["error"] || "Unknown error"
        Rails.logger.warn("Failed to add reaction :#{name}: #{error}")
        # Don't raise, just log - reaction failures are not critical
        response
      end
    rescue StandardError => e
      Rails.logger.warn("Error adding reaction: #{e.message}")
      # Don't raise - reaction failures are not critical
      nil
    end

    # Remove a reaction from a Slack message
    def remove_reaction(slack_installation, channel:, timestamp:, name:)
      bot_token = slack_installation.bot_token
      raise "Bot token not available for installation #{slack_installation.team_id}" unless bot_token

      client = Slack::Web::Client.new(token: bot_token)

      response = client.reactions_remove(
        channel: channel,
        timestamp: timestamp,
        name: name
      )

      if response["ok"]
        Rails.logger.info("Reaction :#{name}: removed from message #{timestamp}")
        response
      else
        error = response["error"] || "Unknown error"
        Rails.logger.warn("Failed to remove reaction :#{name}: #{error}")
        # Don't raise, just log - reaction failures are not critical
        response
      end
    rescue StandardError => e
      Rails.logger.warn("Error removing reaction: #{e.message}")
      # Don't raise - reaction failures are not critical
      nil
    end

    # Get all messages from a Slack thread
    # Returns an array of message hashes with user, text, and ts
    def get_thread_messages(slack_installation, channel:, thread_ts:)
      return [] unless thread_ts

      bot_token = slack_installation.bot_token
      raise "Bot token not available for installation #{slack_installation.team_id}" unless bot_token

      client = Slack::Web::Client.new(token: bot_token)

      response = client.conversations_replies(
        channel: channel,
        ts: thread_ts
      )

      if response["ok"]
        messages = response["messages"] || []
        Rails.logger.info("Retrieved #{messages.count} messages from thread #{thread_ts}")
        
        # Format messages for context
        messages.map do |msg|
          # Extract text from blocks if blocks exist (blocks contain the real content)
          # The text field might just be a fallback like "PR Summary"
          text = if msg["blocks"]
            # Handle both array and string formats
            blocks = if msg["blocks"].is_a?(String)
              begin
                JSON.parse(msg["blocks"])
              rescue JSON::ParserError
                Rails.logger.warn("Failed to parse blocks as JSON: #{msg["blocks"][0..100]}")
                []
              end
            else
              msg["blocks"]
            end
            
            Rails.logger.info("Extracting text from blocks. Block count: #{blocks.is_a?(Array) ? blocks.count : 'not array'}")
            Rails.logger.debug("Blocks data: #{blocks.inspect}")
            
            extracted = extract_text_from_slack_blocks(blocks)
            Rails.logger.info("Extracted text length: #{extracted.length}, original text: #{msg["text"]}")
            
            # Use extracted text if available, otherwise fall back to text field
            # Also extract URLs from the text field if it's a fallback
            text_result = extracted.present? ? extracted : (msg["text"] || "")
            # Extract URLs from markdown in the text result
            extract_urls_from_markdown(text_result)
          else
            # Extract URLs from markdown in plain text messages too
            extract_urls_from_markdown(msg["text"] || "")
          end
          
          {
            user: msg["user"],
            text: text,
            ts: msg["ts"],
            thread_ts: msg["thread_ts"],
            bot_id: msg["bot_id"]
          }
        end
      else
        error = response["error"] || "Unknown error"
        Rails.logger.warn("Failed to get thread messages: #{error}")
        []
      end
    rescue StandardError => e
      Rails.logger.error("Error getting thread messages: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      []
    end

    # Get conversation history for a channel (for DMs)
    # Returns an array of message hashes with user, text, and ts
    def get_conversation_history(slack_installation, channel:, limit: 10)
      return [] unless channel

      bot_token = slack_installation.bot_token
      raise "Bot token not available for installation #{slack_installation.team_id}" unless bot_token

      client = Slack::Web::Client.new(token: bot_token)

      response = client.conversations_history(
        channel: channel,
        limit: limit
      )

      if response["ok"]
        messages = response["messages"] || []
        Rails.logger.info("Retrieved #{messages.count} messages from conversation #{channel}")
        
        # Format messages for context (most recent first, so reverse to get chronological order)
        messages.reverse.map do |msg|
          # Extract text from blocks if blocks exist (blocks contain the real content)
          # The text field might just be a fallback like "PR Summary"
          text = if msg["blocks"]
            # Handle both array and string formats
            blocks = if msg["blocks"].is_a?(String)
              begin
                JSON.parse(msg["blocks"])
              rescue JSON::ParserError
                Rails.logger.warn("Failed to parse blocks as JSON: #{msg["blocks"][0..100]}")
                []
              end
            else
              msg["blocks"]
            end
            
            extracted = extract_text_from_slack_blocks(blocks)
            
            # Use extracted text if available, otherwise fall back to text field
            # Also extract URLs from the text field if it's a fallback
            text_result = extracted.present? ? extracted : (msg["text"] || "")
            # Extract URLs from markdown in the text result
            extract_urls_from_markdown(text_result)
          else
            # Extract URLs from markdown in plain text messages too
            extract_urls_from_markdown(msg["text"] || "")
          end
          
          {
            user: msg["user"],
            text: text,
            ts: msg["ts"],
            bot_id: msg["bot_id"]
          }
        end
      else
        error = response["error"] || "Unknown error"
        Rails.logger.warn("Failed to get conversation history: #{error}")
        []
      end
    rescue StandardError => e
      Rails.logger.error("Error getting conversation history: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      []
    end

    # Extract text content from Slack Block Kit blocks
    def extract_text_from_slack_blocks(blocks)
      return "" unless blocks.is_a?(Array)
      
      Rails.logger.info("Extracting text from #{blocks.count} blocks")
      Rails.logger.debug("Blocks structure: #{JSON.pretty_generate(blocks)}")
      
      text_parts = []
      blocks.each do |block|
        block_type = block["type"] || block[:type]
        Rails.logger.debug("Processing block type: #{block_type}")
        
        case block_type
        when "section"
          # Section blocks can have text or fields
          if block["text"]
            extracted = extract_text_from_block_element(block["text"])
            Rails.logger.debug("Extracted from section.text: #{extracted[0..50]}...") if extracted.present?
            text_parts << extracted if extracted.present?
          end
          if block["fields"]
            block["fields"].each do |field|
              extracted = extract_text_from_block_element(field)
              Rails.logger.debug("Extracted from section.field: #{extracted[0..50]}...") if extracted.present?
              text_parts << extracted if extracted.present?
            end
          end
        when "header"
          if block["text"]
            extracted = extract_text_from_block_element(block["text"])
            Rails.logger.debug("Extracted from header.text: #{extracted[0..50]}...") if extracted.present?
            text_parts << extracted if extracted.present?
          end
        when "context"
          if block["elements"]
            block["elements"].each do |element|
              extracted = extract_text_from_block_element(element)
              Rails.logger.debug("Extracted from context.element: #{extracted[0..50]}...") if extracted.present?
              text_parts << extracted if extracted.present?
            end
          end
        when "divider"
          # No text in dividers
        when "rich_text"
          # Rich text blocks have elements array
          if block["elements"]
            block["elements"].each do |element|
              extracted = extract_text_from_rich_text_element(element)
              Rails.logger.debug("Extracted from rich_text.element: #{extracted[0..50]}...") if extracted.present?
              text_parts << extracted if extracted.present?
            end
          end
        else
          # For other block types, try to find text field
          if block["text"]
            extracted = extract_text_from_block_element(block["text"])
            Rails.logger.debug("Extracted from #{block_type}.text: #{extracted[0..50]}...") if extracted.present?
            text_parts << extracted if extracted.present?
          end
        end
      end
      
      result = text_parts.compact.join("\n").strip
      Rails.logger.info("Extracted text length: #{result.length} characters")
      Rails.logger.debug("Extracted text preview: #{result[0..200]}...") if result.present?
      result
    end
    
    # Extract text from rich text elements (used in rich_text blocks)
    def extract_text_from_rich_text_element(element)
      return "" unless element.is_a?(Hash)
      
      element_type = element["type"] || element[:type]
      case element_type
      when "text"
        text = element["text"] || element[:text] || ""
        # Extract URLs from markdown if present
        extract_urls_from_markdown(text)
      when "link"
        # Rich text link element: has url and text
        url = element["url"] || element[:url] || ""
        link_text = element["text"] || element[:text] || ""
        
        if link_text.present? && link_text != url
          "#{link_text} (#{url})"
        else
          url
        end
      when "rich_text_section"
        if element["elements"]
          element["elements"].map { |e| extract_text_from_rich_text_element(e) }.join("")
        else
          ""
        end
      when "rich_text_list"
        if element["elements"]
          element["elements"].map { |e| extract_text_from_rich_text_element(e) }.join("\n")
        else
          ""
        end
      else
        # For other rich text element types, try to find text
        text = element["text"] || element[:text] || ""
        extract_urls_from_markdown(text)
      end
    end

    def extract_text_from_block_element(element)
      return "" unless element
      
      if element.is_a?(Hash)
        # Slack Block Kit text elements have structure: { "type": "mrkdwn", "text": "actual text" }
        # So we need to check for the "text" key which contains the actual text content
        text = element["text"] || element[:text]
        
        # If text is itself an object (nested structure), recurse
        if text.is_a?(Hash)
          text_content = text["text"] || text[:text] || ""
        else
          text_content = text || ""
        end
        
        # Extract URLs from markdown links in the text
        # Slack markdown format: <url|text> or <url>
        # We want to include both the text and the URL
        text_with_urls = extract_urls_from_markdown(text_content)
        
        text_with_urls
      else
        element.to_s
      end
    end
    
    # Extract URLs from Slack markdown format and include them in the text
    # Format: <url|text> or <url>
    # Returns: "text (url)" or "url" if no text
    def extract_urls_from_markdown(text)
      return "" unless text.is_a?(String)
      
      # Pattern to match Slack markdown links: <url|text> or <url>
      # This regex captures:
      # - Group 1: URL (everything before | or >)
      # - Group 2: Text (optional, everything between | and >)
      text.gsub(/<([^|>]+)(?:\|([^>]+))?>/) do |match|
        url = $1
        link_text = $2
        
        if link_text && link_text != url
          # Both text and URL: include both
          "#{link_text} (#{url})"
        else
          # Only URL: just return the URL
          url
        end
      end
    end

    # Get the Socket Mode running status
    def socket_mode_running?
      @socket_mode_running || false
    end

    # Verify the app token format and provide helpful diagnostics
    def self.verify_app_token
      app_token = ENV["SLACK_APP_TOKEN"]
      
      if app_token.blank?
        return {
          valid: false,
          error: "SLACK_APP_TOKEN is not set in environment variables"
        }
      end

      unless app_token.start_with?("xapp-")
        error = "Token doesn't start with 'xapp-'. "
        if app_token.start_with?("xoxb-")
          error += "You're using a bot token. Socket Mode requires an app-level token."
        elsif app_token.start_with?("xoxp-")
          error += "You're using a user token. Socket Mode requires an app-level token."
        else
          error += "Token format is invalid."
        end
        return { valid: false, error: error }
      end

      {
        valid: true,
        token_prefix: app_token[0..14],
        token_length: app_token.length
      }
    end

    private

    # Step 1: Call apps.connections.open to get a WebSocket URL
    # Documentation: https://docs.slack.dev/apis/events-api/using-socket-mode/#step-1-call-the-appsconnectionsopen-endpoint
    def get_websocket_url
      uri = URI("https://slack.com/api/apps.connections.open")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@app_token}"
      request["Content-Type"] = "application/json"

      response = http.request(request)
      data = JSON.parse(response.body)

      if data["ok"]
        ws_url = data["url"]
        Rails.logger.info("Successfully obtained WebSocket URL from apps.connections.open")
        Rails.logger.debug("WebSocket URL: #{ws_url[0..50]}...")
        ws_url
      else
        error = data["error"] || "Unknown error"
        error_message = "Failed to get WebSocket URL: #{error}"
        Rails.logger.error(error_message)
        Rails.logger.error("Full response: #{data.inspect}")
        
        # Provide helpful error messages
        case error
        when "invalid_auth"
          Rails.logger.error("Authentication failed. Check that:")
          Rails.logger.error("  1. SLACK_APP_TOKEN is correct")
          Rails.logger.error("  2. Token starts with 'xapp-'")
          Rails.logger.error("  3. Token has 'connections:write' scope")
        when "missing_scope"
          Rails.logger.error("Missing required scope. Ensure your app-level token has 'connections:write' scope")
        end
        
        raise error_message
      end
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse response from apps.connections.open: #{e.message}")
      Rails.logger.error("Response body: #{response.body if defined?(response)}")
      raise "Failed to parse WebSocket URL response"
    rescue StandardError => e
      Rails.logger.error("Error calling apps.connections.open: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise
    end

    # Step 2: Connect to the WebSocket URL
    # Documentation: https://docs.slack.dev/apis/events-api/using-socket-mode/#step-2-connect-to-the-websocket
    def connect_socket_mode
      begin
        # Get WebSocket URL from Slack API
        ws_url = get_websocket_url
        
        Rails.logger.info("Connecting to Slack Socket Mode WebSocket...")
        
        # Connect to the WebSocket URL (no authentication needed, URL is already authenticated)
        ws = Faye::WebSocket::Client.new(ws_url)

        @ws_connection = ws

        ws.on :open do |_event|
          Rails.logger.info("Slack Socket Mode WebSocket connection opened successfully")
        end

        ws.on :message do |event|
          begin
            data = JSON.parse(event.data)
            handle_socket_mode_message(data, ws)
          rescue JSON::ParserError => e
            error_msg = "Failed to parse Socket Mode message: #{e.message}"
            Rails.logger.error(error_msg)
            Rails.logger.error("Raw message: #{event.data}")
            STDERR.puts "⚠️  #{error_msg}"
          rescue StandardError => e
            error_msg = "Error handling Socket Mode message: #{e.message}"
            backtrace = e.backtrace.join("\n")
            Rails.logger.error(error_msg)
            Rails.logger.error(backtrace)
            STDERR.puts "\n⚠️  #{error_msg}"
            STDERR.puts backtrace.split("\n").first(5).join("\n") + "\n"
          end
        end

        ws.on :close do |event|
          code = event.code
          reason = event.reason
          
          Rails.logger.warn("Slack Socket Mode WebSocket connection closed: #{code} #{reason}")
          
          @socket_mode_running = false
          
          # Attempt to reconnect after a delay (unless it's a permanent error)
          unless code == 1008 # Policy violation
            EventMachine.add_timer(5) do
              if @socket_mode_running
                Rails.logger.info("Attempting to reconnect Socket Mode...")
                connect_socket_mode
              end
            end
          end
        end

        ws.on :error do |error|
          Rails.logger.error("Slack Socket Mode WebSocket error: #{error}")
          Rails.logger.error("Error class: #{error.class}")
          Rails.logger.error("Error message: #{error.message if error.respond_to?(:message)}")
        end

      rescue StandardError => e
        Rails.logger.error("Failed to establish Socket Mode connection: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        @socket_mode_running = false
        
        # Attempt to reconnect after a delay
        EventMachine.add_timer(10) do
          if @socket_mode_running
            Rails.logger.info("Retrying Socket Mode connection...")
            connect_socket_mode
          end
        end
      end
    end

    # Step 4: Receive events
    # Documentation: https://docs.slack.dev/apis/events-api/using-socket-mode/#step-4-receive-events
    def handle_socket_mode_message(data, ws)
      case data["type"]
      when "events_api"
        handle_events_api(data, ws)
      when "interactive"
        handle_interactive(data, ws)
      when "slash_commands"
        handle_slash_commands(data, ws)
      when "hello"
        Rails.logger.info("Socket Mode hello received - connection ready")
      when "disconnect"
        Rails.logger.warn("Received disconnect message from Slack")
        # Slack is asking us to disconnect, we should reconnect
        @socket_mode_running = false
        EventMachine.add_timer(1) do
          if @socket_mode_running
            connect_socket_mode
          end
        end
      else
        Rails.logger.debug("Unhandled Socket Mode message type: #{data['type']}")
        Rails.logger.debug("Message data: #{data.inspect}")
      end
    end

    def handle_events_api(data, ws)
      envelope_id = data["envelope_id"]
      event = data.dig("payload", "event")
      team_id = data.dig("payload", "team_id")

      return unless event && team_id

      # Log all received events for debugging
      Rails.logger.info("=" * 80)
      Rails.logger.info("📨 Received Slack Event")
      Rails.logger.info("Event Type: #{event['type']}")
      Rails.logger.info("Event Subtype: #{event['subtype'] || 'none'}")
      Rails.logger.info("Team ID: #{team_id}")
      Rails.logger.info("Channel Type: #{event['channel_type'] || 'unknown'}")
      Rails.logger.info("Thread TS: #{event['thread_ts'] || 'none'}")
      Rails.logger.info("Message TS: #{event['ts'] || 'none'}")
      Rails.logger.info("User: #{event['user'] || 'none'}")
      Rails.logger.info("Text: #{event['text'] || 'none'}")
      Rails.logger.info("Full Event Data: #{event.inspect}")
      Rails.logger.info("=" * 80)

      case event["type"]
      when "app_mention"
        handle_app_mention(event, team_id)
      when "message"
        # Skip message subtypes (message_changed, message_deleted, etc.)
        # We only want to process actual new messages
        if event["subtype"]
          Rails.logger.info("Skipping message with subtype: #{event['subtype']}")
        else
          handle_message(event, team_id)
        end
      else
        Rails.logger.info("Unhandled event type: #{event['type']}")
      end

      # Step 5: Acknowledge events (required)
      acknowledge_event(ws, envelope_id)
    end

    def handle_interactive(data, ws)
      # Handle interactive components (buttons, modals, etc.)
      Rails.logger.debug("Interactive event received: #{data.inspect}")
      # Acknowledge if needed
      acknowledge_event(ws, data["envelope_id"]) if data["envelope_id"]
    end

    def handle_slash_commands(data, ws)
      # Handle slash commands
      Rails.logger.debug("Slash command received: #{data.inspect}")
      # Acknowledge if needed
      acknowledge_event(ws, data["envelope_id"]) if data["envelope_id"]
    end

    # Step 5: Acknowledge events
    # Documentation: https://docs.slack.dev/apis/events-api/using-socket-mode/#step-5-acknowledge-events
    def acknowledge_event(ws, envelope_id)
      return unless envelope_id && ws

      acknowledgment = {
        envelope_id: envelope_id
      }
      
      ws.send(JSON.generate(acknowledgment))
      Rails.logger.debug("Acknowledged event: #{envelope_id}")
    rescue StandardError => e
      Rails.logger.error("Failed to acknowledge Socket Mode event: #{e.message}")
    end

    def handle_app_mention(event_data, team_id)
      Rails.logger.info("🤖 Handling app mention/message")
      Rails.logger.info("Event data: #{event_data.inspect}")

      # Extract event data
      channel_id = event_data["channel"]
      user_id = event_data["user"]
      text = event_data["text"]
      message_ts = event_data["ts"]
      
      # Only use thread_ts if the message is actually in a thread
      # A real thread means thread_ts exists and is different from message_ts
      # In DMs, if thread_ts != message_ts, it means the user explicitly replied in a thread
      # In channels, if thread_ts != message_ts, it's also a real thread
      raw_thread_ts = event_data["thread_ts"]
      
      thread_ts = if raw_thread_ts && raw_thread_ts != message_ts
        # This is a real thread (user explicitly replied to a message)
        raw_thread_ts
      else
        # Not in a thread (message at channel/DM level)
        nil
      end

      Rails.logger.info("📝 Message Details:")
      Rails.logger.info("  Channel ID: #{channel_id}")
      Rails.logger.info("  Channel Type: #{event_data['channel_type']}")
      Rails.logger.info("  Thread TS: #{thread_ts}")
      Rails.logger.info("  User ID: #{user_id}")
      Rails.logger.info("  Message TS: #{message_ts}")
      Rails.logger.info("  Text: #{text}")

      # Skip bot messages
      if event_data["bot_id"]
        Rails.logger.info("⏭️  Skipping bot message")
        return
      end

      # Find installation
      installation = SlackInstallation.find_by(team_id: team_id)
      unless installation
        Rails.logger.warn("⚠️  No installation found for team_id: #{team_id}")
        return
      end

      Rails.logger.info("✅ Found installation: #{installation.team_name} (ID: #{installation.id})")
      Rails.logger.info("🚀 Queuing ProcessSlackMessageJob...")

      # Queue job to process message
      ProcessSlackMessageJob.perform_later(
        installation_id: installation.id,
        channel_id: channel_id,
        thread_ts: thread_ts,
        user_id: user_id,
        text: text,
        message_ts: message_ts
      )
      
      Rails.logger.info("✅ Job queued successfully")
    end

    def handle_message(event_data, team_id)
      Rails.logger.info("💬 Processing message event")
      Rails.logger.info("Channel: #{event_data['channel']}")
      Rails.logger.info("Channel Type: #{event_data['channel_type']}")
      Rails.logger.info("User: #{event_data['user']}")
      Rails.logger.info("Text: #{event_data['text']}")
      Rails.logger.info("Thread TS: #{event_data['thread_ts']}")
      Rails.logger.info("Bot ID: #{event_data['bot_id']}")
      
      # Skip bot messages
      if event_data["bot_id"]
        Rails.logger.info("⏭️  Skipping bot message")
        return
      end
      
      # Skip messages without text
      unless event_data["text"]
        Rails.logger.info("⏭️  Skipping message without text")
        return
      end

      # Only handle messages in threads (where we have PR context)
      # or direct messages
      channel_type = event_data["channel_type"]
      thread_ts = event_data["thread_ts"]
      
      Rails.logger.info("Channel type: #{channel_type}, Thread TS: #{thread_ts}")
      
      # Process if it's a DM or a thread reply
      if channel_type == "im" || thread_ts
        Rails.logger.info("✅ Processing as DM or thread message")
        handle_app_mention(event_data, team_id)
      else
        Rails.logger.info("⏭️  Skipping - not a DM or thread message")
      end
    end
  end
end
