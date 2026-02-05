# frozen_string_literal: true

class ProcessSlackMessageJob < ApplicationJob
  queue_as :default

  def perform(installation_id:, channel_id:, thread_ts:, user_id:, text:, message_ts:)
    installation = SlackInstallation.find_by(id: installation_id)
    unless installation
      Rails.logger.error("❌ Installation not found: #{installation_id}")
      return
    end

    # Find or create user
    user = User.find_or_create_by!(
      slack_installation: installation,
      slack_user_id: user_id
    )

    # Find associated PR via SlackThread
    slack_thread = SlackThread.find_by(
      slack_installation: installation,
      slack_channel_id: channel_id,
      slack_thread_ts: thread_ts
    )

    pull_request = slack_thread&.pull_request

    # Add loading indicator (reaction)
    SlackService.add_reaction(
      installation,
      channel: channel_id,
      timestamp: message_ts,
      name: "eyes"
    )

    # Process the message
    chatbot = ChatbotService.new(installation, user, pull_request: pull_request)
    chatbot.process_message(text, channel_id: channel_id, thread_ts: thread_ts)
  rescue StandardError => e
    error_msg = "❌ Failed to process Slack message: #{e.message}"
    backtrace = e.backtrace.join("\n")
    
    # Log to file
    Rails.logger.error(error_msg)
    Rails.logger.error(backtrace)
    
    # Also output to STDERR for immediate visibility in console
    STDERR.puts "\n" + "=" * 80
    STDERR.puts error_msg
    STDERR.puts backtrace
    STDERR.puts "=" * 80 + "\n"
    
    raise
  ensure
    # Remove loading indicator (reaction) in all cases
    if installation && message_ts
      SlackService.remove_reaction(
        installation,
        channel: channel_id,
        timestamp: message_ts,
        name: "eyes"
      )
    end
  end
end
