# frozen_string_literal: true

module AIProviders
  class BaseProvider
    # Chat completion for general conversation
    # @param messages [Array<Hash>] Array of message hashes with :role and :content
    # @param options [Hash] Additional options (temperature, max_tokens, etc.)
    # @return [String] The AI response text
    def chat_completion(messages, options = {})
      raise NotImplementedError, "Subclasses must implement chat_completion"
    end

    # Structured output for intent detection
    # @param messages [Array<Hash>] Array of message hashes with :role and :content
    # @param schema [Hash] JSON schema or function definition for structured output
    # @param options [Hash] Additional options
    # @return [Hash] Structured response with intent and parameters
    def structured_output(messages, schema, options = {})
      raise NotImplementedError, "Subclasses must implement structured_output"
    end
  end
end
