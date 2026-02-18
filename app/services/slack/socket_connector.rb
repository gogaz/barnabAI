# frozen_string_literal: true

require "faye/websocket"
require "eventmachine"
require "json"
require "net/http"
require "uri"

module Slack
  # Handles Slack Socket Mode WebSocket connection, reconnection, and event processing
  # Following official Slack documentation: https://docs.slack.dev/apis/events-api/using-socket-mode/#implementing
  class SocketConnector
    class << self
      # Start Slack Socket Mode connection
      # This creates a single global connection that handles events for all workspaces
      # EventMachine.run blocks the current thread, keeping the process alive
      # @param app_token [String] The Slack app token
      def start(app_token:)
        return if running?

        @socket_mode_running = true
        @app_token = app_token
        @connection_established = false
        @reconnect_attempts = 0
        @max_reconnect_attempts = 10
        @reconnecting = false

        # Run in current thread - EventMachine.run blocks and keeps the process alive
        EventMachine.run do
          connect_socket_mode
          start_health_check
        end
      rescue StandardError
        @socket_mode_running = false
        @connection_established = false
        raise
      end

      # Get the Socket Mode running status
      def running?
        @socket_mode_running || false
      end

      # Get the actual connection status (more accurate than running?)
      def connection_established?
        @connection_established && @ws_connection && @ws_connection.ready_state == 1
      rescue StandardError
        false
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
          Rails.logger.info("Successfully obtained WebSocket URL from Slack API")
          ws_url
        else
          error = data["error"] || "Unknown error"
          error_message = "Failed to get WebSocket URL from Slack API: #{error}"
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
          ws_url = get_websocket_url

          Rails.logger.info("Connecting to Slack Socket Mode WebSocket...")

          ws = Faye::WebSocket::Client.new(ws_url)

          @ws_connection = ws

          ws.on :open do |_event|
            Rails.logger.info("Slack Socket Mode WebSocket connection opened successfully")
            @connection_established = true
            @reconnect_attempts = 0  # Reset on successful connection
            @reconnecting = false
            @last_heartbeat = Time.now
          end

          ws.on :message do |event|
            begin
              data = JSON.parse(event.data)
              handle_message(data, ws)
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

            @connection_established = false
            @ws_connection = nil

            # Attempt to reconnect after a delay (unless it's a permanent error)
            unless code == 1008 # Policy violation
              attempt_reconnect
            else
              Rails.logger.error("Socket Mode connection closed due to policy violation. Stopping reconnection attempts.")
              @socket_mode_running = false
              raise "Slack Socket Mode connection closed due to policy violation: #{reason}"
            end
          end

          ws.on :error do |error|
            Rails.logger.error("Slack Socket Mode WebSocket error: #{error}")
            Rails.logger.error("Error class: #{error.class}")
            Rails.logger.error("Error message: #{error.message if error.respond_to?(:message)}")
            @connection_established = false
          end

        rescue StandardError => e
          Rails.logger.error("Failed to establish Socket Mode connection: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          @connection_established = false
          @ws_connection = nil

          # Attempt to reconnect after a delay
          attempt_reconnect
        end
      end

      # Attempt to reconnect with exponential backoff
      def attempt_reconnect
        return unless @socket_mode_running
        return if @reconnecting

        @reconnecting = true
        @reconnect_attempts += 1

        if @reconnect_attempts > @max_reconnect_attempts
          Rails.logger.error("Max reconnection attempts (#{@max_reconnect_attempts}) reached. Stopping Socket Mode.")
          @socket_mode_running = false
          @reconnecting = false
          raise "Slack Socket Mode failed to reconnect after #{@max_reconnect_attempts} attempts"
        end

        # Exponential backoff: 5s, 10s, 20s, 40s, etc., max 60s
        delay = [5 * (2 ** (@reconnect_attempts - 1)), 60].min

        Rails.logger.info("Attempting to reconnect Socket Mode (attempt #{@reconnect_attempts}/#{@max_reconnect_attempts}) in #{delay}s...")

        EventMachine.add_timer(delay) do
          @reconnecting = false
          if @socket_mode_running
            connect_socket_mode
          end
        end
      end

      # Start periodic health check
      def start_health_check
        # Check connection health every 30 seconds
        EventMachine.add_periodic_timer(30) do
          check_connection_health
        end
      end

      # Check if the WebSocket connection is actually alive
      def check_connection_health
        return unless @socket_mode_running

        # Check if we have a connection object
        if @ws_connection.nil?
          Rails.logger.warn("Socket Mode connection object is nil but socket_mode_running is true. Attempting reconnect...")
          @connection_established = false
          attempt_reconnect
          return
        end

        # Check connection state using Faye WebSocket API
        # Faye::WebSocket::Client has a ready_state method:
        # 0 = CONNECTING, 1 = OPEN, 2 = CLOSING, 3 = CLOSED
        begin
          ready_state = @ws_connection.ready_state

          if ready_state != 1 # Not OPEN
            Rails.logger.warn("Socket Mode connection state is #{ready_state} (expected 1=OPEN). Connection appears disconnected.")
            @connection_established = false
            @ws_connection = nil

            # Only attempt reconnect if we're supposed to be running
            if @socket_mode_running
              attempt_reconnect
            end
          else
            # Connection is open, update last heartbeat
            @last_heartbeat = Time.now if defined?(@last_heartbeat)
          end
        rescue StandardError => e
          Rails.logger.error("Error checking Socket Mode connection health: #{e.message}")
          # If we can't check the state, assume it's disconnected
          @connection_established = false
          @ws_connection = nil

          if @socket_mode_running
            attempt_reconnect
          end
        end
      end

      # Step 4: Receive events
      # Documentation: https://docs.slack.dev/apis/events-api/using-socket-mode/#step-4-receive-events
      def handle_message(data, ws)
        message_type = data["type"]
        Rails.logger.info("handle_message: message_type=#{message_type}")
        
        case message_type
        when "events_api"
          handle_events_api(data, ws)
        when "interactive"
          handle_interactive(data, ws)
        when "slash_commands"
          handle_slash_commands(data, ws)
        when "hello"
          Rails.logger.info("Socket Mode hello received - connection ready")
          @connection_established = true
          @reconnect_attempts = 0  # Reset reconnect attempts on successful connection
          @last_heartbeat = Time.now
        when "disconnect"
          Rails.logger.warn("Received disconnect message from Slack")
          # Slack is asking us to disconnect, we should reconnect
          @connection_established = false
          @ws_connection = nil
          EventMachine.add_timer(1) do
            if @socket_mode_running
              connect_socket_mode
            end
          end
        else
          Rails.logger.debug("Unhandled message type: #{message_type}")
          nil
        end
      end

      def handle_events_api(data, ws)
        envelope_id = data["envelope_id"]
        event = data.dig("payload", "event")
        team_id = data.dig("payload", "team_id")

        Rails.logger.info("handle_events_api: envelope_id=#{envelope_id}, event_type=#{event&.[]('type')}, team_id=#{team_id}")

        unless event && team_id
          Rails.logger.warn("handle_events_api: Missing event or team_id. event=#{event.inspect}, team_id=#{team_id}")
          acknowledge_event(ws, envelope_id) if envelope_id
          return
        end

        case event["type"]
        when "app_mention"
          Rails.logger.info("Processing app_mention event")
          handle_app_mention(event, team_id)
        when "message"
          # Skip message subtypes (message_changed, message_deleted, etc.)
          # We only want to process actual new messages
          if event["subtype"]
            Rails.logger.debug("Skipping message with subtype: #{event['subtype']}")
          else
            Rails.logger.info("Processing message event")
            handle_slack_message_event(event, team_id)
          end
        else
          Rails.logger.debug("Unhandled event type: #{event['type']}")
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

        # Check if connection is actually open before sending
        if ws.ready_state != 1 # Not OPEN
          Rails.logger.warn("Cannot acknowledge event #{envelope_id}: WebSocket is not open (state: #{ws.ready_state})")
          return
        end

        acknowledgment = {
          envelope_id: envelope_id
        }

        ws.send(JSON.generate(acknowledgment))
        Rails.logger.debug("Acknowledged event: #{envelope_id}")
        @last_heartbeat = Time.now if defined?(@last_heartbeat)
      rescue StandardError => e
        Rails.logger.error("Failed to acknowledge Socket Mode event: #{e.message}")
        # If send fails, connection might be dead
        if e.message.include?("not open") || e.message.include?("closed")
          @connection_established = false
          @ws_connection = nil
          attempt_reconnect if @socket_mode_running
        end
      end

      def handle_app_mention(event_data, team_id)
        # Extract event data
        channel_id = event_data["channel"]
        user_id = event_data["user"]
        text = event_data["text"]
        message_ts = event_data["ts"]

        Rails.logger.info("handle_app_mention: channel_id=#{channel_id}, user_id=#{user_id}, text=#{text&.[](0..50)}..., message_ts=#{message_ts}")

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
        if event_data["bot_id"]
          Rails.logger.debug("Skipping bot message: bot_id=#{event_data['bot_id']}")
          return
        end

        Rails.logger.info("Enqueuing ProcessSlackMessageJob for channel_id=#{channel_id}, thread_ts=#{thread_ts}")

        # Queue job to process message
        ProcessSlackMessageJob.perform_later(
          channel_id: channel_id,
          thread_ts: thread_ts,
          user_id: user_id,
          text: text,
          message_ts: message_ts
        )

        Rails.logger.info("ProcessSlackMessageJob enqueued successfully")
      end

      def handle_slack_message_event(event_data, team_id)
        Rails.logger.info("handle_slack_message_event: event_type=message, channel_type=#{event_data['channel_type']}, thread_ts=#{event_data['thread_ts']}")

        # Skip bot messages
        if event_data["bot_id"]
          Rails.logger.debug("Skipping bot message: bot_id=#{event_data['bot_id']}")
          return
        end

        # Skip messages without text
        unless event_data["text"]
          Rails.logger.debug("Skipping message without text")
          return
        end

        # Only handle messages in threads (where we have PR context)
        # or direct messages
        channel_type = event_data["channel_type"]
        thread_ts = event_data["thread_ts"]

        # Process if it's a DM or a thread reply
        if channel_type == "im" || thread_ts
          Rails.logger.info("Processing message: channel_type=#{channel_type}, thread_ts=#{thread_ts}")
          handle_app_mention(event_data, team_id)
        else
          Rails.logger.debug("Skipping message: not a DM or thread (channel_type=#{channel_type}, thread_ts=#{thread_ts})")
        end
      end
    end
  end
end
