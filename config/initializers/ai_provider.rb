# frozen_string_literal: true

# AI Provider configuration
# The AI provider is configured via environment variables:
# - AI_PROVIDER: The provider to use (default: "gemini")
# - GEMINI_API_KEY: Required for Gemini provider
# - GEMINI_MODEL: Model to use (default: "gemini-pro")
# - OPENAI_API_KEY: Required for OpenAI provider
# - OPENAI_MODEL: Model to use (default: "gpt-4o")

Rails.application.config.ai_provider = ENV.fetch("AI_PROVIDER", "gemini")

# Validate required environment variables on boot
if Rails.env.production?
  case Rails.application.config.ai_provider.downcase
  when "gemini"
    unless ENV["GEMINI_API_KEY"]
      raise "GEMINI_API_KEY environment variable is required for Gemini provider"
    end
  when "openai"
    unless ENV["OPENAI_API_KEY"]
      raise "OPENAI_API_KEY environment variable is required for OpenAI provider"
    end
  end
end
