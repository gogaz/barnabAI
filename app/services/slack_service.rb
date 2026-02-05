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
            
            extracted = Slack::TextExtractor.extract_text_from_slack_blocks(blocks)
            
            # Use extracted text if available, otherwise fall back to text field
            # Also extract URLs from the text field if it's a fallback
            text_result = extracted.present? ? extracted : (msg["text"] || "")
            # Extract URLs from markdown in the text result
            Slack::TextExtractor.extract_urls_from_markdown(text_result)
          else
            # Extract URLs from markdown in plain text messages too
            Slack::TextExtractor.extract_urls_from_markdown(msg["text"] || "")
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
            
            extracted = Slack::TextExtractor.extract_text_from_slack_blocks(blocks)
            
            # Use extracted text if available, otherwise fall back to text field
            # Also extract URLs from the text field if it's a fallback
            text_result = extracted.present? ? extracted : (msg["text"] || "")
            # Extract URLs from markdown in the text result
            Slack::TextExtractor.extract_urls_from_markdown(text_result)
          else
            # Extract URLs from markdown in plain text messages too
            Slack::TextExtractor.extract_urls_from_markdown(msg["text"] || "")
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
          rescue StandardError => e
            error_msg = "Error handling Socket Mode message: #{e.message}"
            backtrace = e.backtrace.join("\n")
            Rails.logger.error(error_msg)
            Rails.logger.error(backtrace)
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
      end
    end

    def handle_events_api(data, ws)
      envelope_id = data["envelope_id"]
      event = data.dig("payload", "event")
      team_id = data.dig("payload", "team_id")

      return unless event && team_id

      case event["type"]
      when "app_mention"
        handle_app_mention(event, team_id)
      when "message"
        # Skip message subtypes (message_changed, message_deleted, etc.)
        # We only want to process actual new messages
        handle_message(event, team_id) unless event["subtype"]
      end

      # Step 5: Acknowledge events (required)
      acknowledge_event(ws, envelope_id)
    end

    def handle_interactive(data, ws)
      # Handle interactive components (buttons, modals, etc.)
      # Acknowledge if needed
      acknowledge_event(ws, data["envelope_id"]) if data["envelope_id"]
    end

    def handle_slash_commands(data, ws)
      # Handle slash commands
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

      # Skip bot messages
      return if event_data["bot_id"]

      # Find installation
      installation = SlackInstallation.find_by(team_id: team_id)
      return unless installation

      # Queue job to process message
      ProcessSlackMessageJob.perform_later(
        installation_id: installation.id,
        channel_id: channel_id,
        thread_ts: thread_ts,
        user_id: user_id,
        text: text,
        message_ts: message_ts
      )
    end

    def handle_message(event_data, team_id)
      # Skip bot messages
      return if event_data["bot_id"]
      
      # Skip messages without text
      return unless event_data["text"]

      # Only handle messages in threads (where we have PR context)
      # or direct messages
      channel_type = event_data["channel_type"]
      thread_ts = event_data["thread_ts"]
      
      # Process if it's a DM or a thread reply
      if channel_type == "im" || thread_ts
        handle_app_mention(event_data, team_id)
      end
    end
  end
end
