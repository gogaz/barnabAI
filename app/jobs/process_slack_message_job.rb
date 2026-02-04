# frozen_string_literal: true

class ProcessSlackMessageJob < ApplicationJob
  queue_as :default

  def perform(installation_id:, channel_id:, thread_ts:, user_id:, text:, message_ts:)
    Rails.logger.info("=" * 80)
    Rails.logger.info("🔄 ProcessSlackMessageJob started")
    Rails.logger.info("Installation ID: #{installation_id}")
    Rails.logger.info("Channel ID: #{channel_id}")
    Rails.logger.info("Thread TS: #{thread_ts}")
    Rails.logger.info("User ID: #{user_id}")
    Rails.logger.info("Message TS: #{message_ts}")
    Rails.logger.info("Message Text: #{text}")
    Rails.logger.info("=" * 80)

    installation = SlackInstallation.find_by(id: installation_id)
    unless installation
      Rails.logger.error("❌ Installation not found: #{installation_id}")
      return
    end

    Rails.logger.info("✅ Found installation: #{installation.team_name}")

    # Find or create user
    user = User.find_or_create_by!(
      slack_installation: installation,
      slack_user_id: user_id
    )
    Rails.logger.info("✅ Found/created user: #{user.slack_user_id}")

    # Find associated PR via SlackThread
    slack_thread = SlackThread.find_by(
      slack_installation: installation,
      slack_channel_id: channel_id,
      slack_thread_ts: thread_ts
    )

    pull_request = slack_thread&.pull_request
    if pull_request
      Rails.logger.info("✅ Found associated PR: #{pull_request.title}")
    else
      Rails.logger.info("ℹ️  No associated PR found (this is a standalone message)")
    end

    # Process the message
    Rails.logger.info("🤖 Processing message with ChatbotService...")
    chatbot = ChatbotService.new(installation, user, pull_request: pull_request)
    chatbot.process_message(text, channel_id: channel_id, thread_ts: thread_ts)
    Rails.logger.info("✅ Message processed successfully")
  rescue NameError => e
    # Re-raise NameError (uninitialized constant) to avoid silent failures
    error_msg = "❌ NameError in ProcessSlackMessageJob: #{e.message}"
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
  end
end
