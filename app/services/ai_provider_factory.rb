# frozen_string_literal: true

class AIProviderFactory
  def self.create
    provider_name = ENV.fetch("AI_PROVIDER", "gemini").downcase

    case provider_name
    when "gemini"
      create_gemini_provider
    when "openai"
      create_openai_provider
    else
      raise ArgumentError, "Unknown AI provider: #{provider_name}. Supported: gemini, openai"
    end
  end

  private

  def self.create_gemini_provider
    api_key = ENV.fetch("GEMINI_API_KEY") do
      raise ArgumentError, "GEMINI_API_KEY environment variable is required"
    end

    model = ENV.fetch("GEMINI_MODEL", "gemini-pro")

    AIProviders::GeminiProvider.new(api_key: api_key, model: model)
  end

  def self.create_openai_provider
    api_key = ENV.fetch("OPENAI_API_KEY") do
      raise ArgumentError, "OPENAI_API_KEY environment variable is required"
    end

    model = ENV.fetch("OPENAI_MODEL", "gpt-4o")

    AIProviders::OpenAIProvider.new(api_key: api_key, model: model)
  end
end
