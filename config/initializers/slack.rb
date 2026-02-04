# frozen_string_literal: true

# Slack configuration
# Required environment variables:
# - SLACK_CLIENT_ID: Your Slack app's client ID
# - SLACK_CLIENT_SECRET: Your Slack app's client secret
# - SLACK_APP_TOKEN: App-level token for Socket Mode (same for all workspaces)

if Rails.env.production?
  unless ENV["SLACK_CLIENT_ID"]
    Rails.logger.warn "SLACK_CLIENT_ID environment variable is not set"
  end

  unless ENV["SLACK_CLIENT_SECRET"]
    Rails.logger.warn "SLACK_CLIENT_SECRET environment variable is not set"
  end

  unless ENV["SLACK_APP_TOKEN"]
    Rails.logger.warn "SLACK_APP_TOKEN environment variable is not set (required for Socket Mode)"
  end
end
