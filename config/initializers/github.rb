# frozen_string_literal: true

# GitHub OAuth configuration
# Required environment variables:
# - GITHUB_CLIENT_ID: Your GitHub OAuth app's client ID
# - GITHUB_CLIENT_SECRET: Your GitHub OAuth app's client secret

if Rails.env.production?
  unless ENV["GITHUB_CLIENT_ID"]
    Rails.logger.warn "GITHUB_CLIENT_ID environment variable is not set"
  end

  unless ENV["GITHUB_CLIENT_SECRET"]
    Rails.logger.warn "GITHUB_CLIENT_SECRET environment variable is not set"
  end
end
