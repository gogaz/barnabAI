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

    # Structured output using function calling
    # @param structured_prompt [Hash] Hash with :messages (provider-specific format) and :functions (function declarations)
    # @param options [Hash] Additional options
    # @option options [Boolean] :allow_multiple Whether to allow multiple function calls (default: false)
    # @return [Hash, Array<Hash>] Function call(s) with :name and :parameters
    def structured_output(structured_prompt, options = {})
      raise NotImplementedError, "Subclasses must implement structured_output"
    end
  end
end
