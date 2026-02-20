# frozen_string_literal: true

class AIProviderFactory
  def self.create(_user)
    api_key = ENV.fetch("GEMINI_API_KEY") do
      raise ArgumentError, "GEMINI_API_KEY environment variable is required"
    end

    model = ENV.fetch("GEMINI_MODEL", "gemini-pro")

    AIProviders::GeminiProvider.new(api_key: api_key, model: model)
  end
end
