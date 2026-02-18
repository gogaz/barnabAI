# frozen_string_literal: true

require "slack-ruby-client"
require "json"

module Slack
  class Client
    class << self
      # Send a message to a Slack channel
      # Accepts a hash with :text and/or :blocks keys (from MessageBuilder.to_h)
      def send_message(channel:, thread_ts: nil, **message_options)
        bot_token = ENV["SLACK_BOT_TOKEN"]
        raise "SLACK_BOT_TOKEN not set in environment variables" unless bot_token

        client = Slack::Web::Client.new(token: bot_token)

        options = {
          channel: channel,
          # Disable "unfurling" of links and media by default to prevent unwanted previews in messages
          unfurl_links: message_options[:unfurl_links] || false,
          unfurl_media: message_options[:unfurl_media] || false
        }
        
        if message_options[:blocks].present?
          parsed_blocks = if message_options[:blocks].is_a?(String)
            JSON.parse(message_options[:blocks])
          else
            message_options[:blocks]
          end
          options[:blocks] = parsed_blocks
          options[:text] = message_options[:text] || "Preview not available" # Fallback text for notifications and accessibility
        elsif message_options[:text].present?
          options[:text] = message_options[:text]
        end
        
        options[:thread_ts] = thread_ts if thread_ts

        puts "THIS IS THE SLACK MESSAGE OPTIONS HASH"
        puts options.inspect
        puts "END OF OPTIONS HASH"
        response = client.chat_postMessage(options)

        if response["ok"]
          response
        else
          raise "Failed to send Slack message: #{response.inspect}"
        end
      end

      # Add a reaction to a Slack message
      def add_reaction(channel:, timestamp:, name:)
        bot_token = ENV["SLACK_BOT_TOKEN"]
        raise "SLACK_BOT_TOKEN not set in environment variables" unless bot_token

        client = Slack::Web::Client.new(token: bot_token)

        response = client.reactions_add(
          channel: channel,
          timestamp: timestamp,
          name: name
        )

        if response["ok"]
          response
        else
          Rails.logger.error("Error adding reaction #{name} to channel #{channel}: #{response.inspect}")
          response
        end
      rescue StandardError => e
        Rails.logger.error("Error adding reaction #{name} to channel #{channel}: #{e.message}\n#{e.backtrace.join("\n")}")
        # Don't raise - reaction failures are not critical
        nil
      end

      # Remove a reaction from a Slack message
      def remove_reaction(channel:, timestamp:, name:)
        bot_token = ENV["SLACK_BOT_TOKEN"]
        raise "SLACK_BOT_TOKEN not set in environment variables" unless bot_token

        client = Slack::Web::Client.new(token: bot_token)

        response = client.reactions_remove(
          channel: channel,
          timestamp: timestamp,
          name: name
        )

        if response["ok"]
          response
        else
          Rails.logger.error("Error removing reaction #{name} to channel #{channel}: #{response.inspect}")
        end
      rescue StandardError => e
        Rails.logger.error("Error removing reaction #{name} to channel #{channel}: #{e.message}\n#{e.backtrace.join("\n")}")
        # Don't raise - reaction failures are not critical
        nil
      end

      # Get all messages from a Slack thread
      # Returns an array of message hashes with user, text, and ts
      def get_thread_messages(channel:, thread_ts:)
        return [] unless thread_ts

        bot_token = ENV["SLACK_BOT_TOKEN"]
        raise "SLACK_BOT_TOKEN not set in environment variables" unless bot_token

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
            {
              user: msg["user"],
              text: msg["blocks"] || msg["text"],
              ts: msg["ts"],
              bot_id: msg["bot_id"]
            }
          end
        else
          Rails.logger.warn("Failed to get thread messages: #{response.inspect}")
          []
        end
      rescue StandardError => e
        Rails.logger.error("Error getting thread messages on thread #{thread_ts} in channel #{channel}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        []
      end

      # Get conversation history for a channel (for DMs)
      # Returns an array of message hashes with user, text, and ts
      def get_conversation_history(channel:, limit: 10)
        return [] unless channel

        bot_token = ENV["SLACK_BOT_TOKEN"]
        raise "SLACK_BOT_TOKEN not set in environment variables" unless bot_token

        client = Slack::Web::Client.new(token: bot_token)

        response = client.conversations_history(
          channel: channel,
          limit: limit
        )

        if response["ok"]
          messages = response["messages"] || []

          # reverse to get chronological order
          messages.reverse.map do |msg|
            {
              user: msg["user"],
              text: msg["blocks"] || msg["text"],
              ts: msg["ts"],
              bot_id: msg["bot_id"]
            }
          end
        else
          Rails.logger.warn("Failed to get conversation history: #{response.inspect}")
          []
        end
      rescue StandardError => e
        Rails.logger.error("Error getting conversation history: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        []
      end

      def set_thread_typing_status(channel, thread_ts, status)
        bot_token = ENV["SLACK_BOT_TOKEN"]
        raise "SLACK_BOT_TOKEN not set in environment variables" unless bot_token

        return if thread_ts.blank?

        client = Slack::Web::Client.new(token: bot_token)

        client.assistant_threads_setStatus(channel_id: channel, thread_ts: thread_ts, status: status)
      end

      # Get user info from Slack
      # Returns a hash with user profile information
      def get_user_info(user_id:)
        bot_token = ENV["SLACK_BOT_TOKEN"]
        raise "SLACK_BOT_TOKEN not set in environment variables" unless bot_token

        client = Slack::Web::Client.new(token: bot_token)

        response = client.users_info(user: user_id)

        if response["ok"]
          user = response["user"] || {}
          profile = user["profile"] || {}
          {
            id: user["id"],
            name: user["name"],
            real_name: user["real_name"] || profile["real_name"],
            display_name: profile["display_name"],
            email: profile["email"]
          }
        else
          Rails.logger.warn("Failed to get user info for #{user_id}: #{response.inspect}")
          {}
        end
      rescue StandardError => e
        Rails.logger.error("Error getting user info for #{user_id}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        {}
      end

      def extract_mentioned_user_ids(text)
        return [] unless text

        mention_pattern = /<@([UW][A-Z0-9]+)>/
        text.scan(mention_pattern).flatten.uniq.reject { |id| id == ENV["SLACK_BOT_USER_ID"] }
      end
    end
  end
end
