# frozen_string_literal: true

class ProcessSlackMessageJob < ApplicationJob
  queue_as :default

  def perform(channel_id:, thread_ts:, user_id:, text:, message_ts:)
    user = User.find_or_create_by!(slack_user_id: user_id)

    # Loading indicator
    Slack::Client.add_reaction(name: "eyes", channel: channel_id, timestamp: message_ts)

    chatbot = ChatbotService.new(user)
    chatbot.process_message(text, channel_id: channel_id, thread_ts: thread_ts, message_ts: message_ts)
  rescue StandardError => e
    error_msg = "❌ Failed to process Slack message: #{e.message}"
    backtrace = e.backtrace.join("\n")
    
    # Log to file
    Rails.logger.error(error_msg)
    Rails.logger.error(backtrace)
    
    # Also output to STDERR for immediate visibility in console
    STDERR.puts error_msg
    STDERR.puts backtrace

    # Send error message to user
    error_message = "Sorry, I encountered an error processing your request: #{e.message}"
    error_builder = Slack::MessageBuilder.new(text: error_message)
    
    Slack::Client.send_message(
      channel: user_id,
      thread_ts: thread_ts || message_ts,
      **error_builder.to_h
    )

    # Re-raise to mark job as failed (no retry by default in ActiveJob)
    raise e
  ensure
    # Remove loading indicator (reaction) in all cases
    if message_ts
      Slack::Client.remove_reaction(
        channel: channel_id,
        timestamp: message_ts,
        name: "eyes"
      )
    end
  end
end
