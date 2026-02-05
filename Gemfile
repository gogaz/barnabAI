# frozen_string_literal: true

source "https://rubygems.org"

ruby "4.0.1"

gem "rails", "~> 8.1"

# Use the Puma web server
gem "puma", ">= 5.0"

# Use Kredis to get higher-level data types in Redis
gem "kredis"

# Background job processing
gem "solid_queue"

# Use Active Model has_secure_password
gem "bcrypt", "~> 3.1.7"

# PostgreSQL adapter
gem "pg", "~> 1.5"

# Slack integration
gem "slack-ruby-client", "~> 3.1.0"
gem "faye-websocket", "~> 0.11"
gem "eventmachine", "~> 1.2"

# GitHub API client
gem "octokit", "~> 7.0"

# CODEOWNERS file parser
gem "codeowner_parser"


# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ]
  # Load environment variables from .env file
  gem "dotenv-rails"
end

# Speed up boot time by caching expensive operations
gem "bootsnap", ">= 1.4.4", require: false

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end
