# frozen_string_literal: true

require "openai"

module AIProviders
  class OpenAIProvider < BaseProvider
    def initialize(api_key:, model: "gpt-4")
      @client = OpenAI::Client.new(access_token: api_key)
      @model = model
    end

    def chat_completion(messages, options = {})
      response = @client.chat(
        parameters: {
          model: @model,
          messages: format_messages(messages),
          temperature: options[:temperature] || 0.7,
          max_tokens: options[:max_tokens] || 1000
        }.compact
      )

      response.dig("choices", 0, "message", "content")
    rescue StandardError => e
      Rails.logger.error("OpenAI API error: #{e.message}")
      raise
    end

    def structured_output(messages, schema, options = {})
      # Use function calling for structured output
      functions = [{
        name: schema[:function_name] || "detect_intent",
        description: schema[:description] || "Detect user intent from the conversation",
        parameters: schema[:parameters] || {}
      }]

      response = @client.chat(
        parameters: {
          model: @model,
          messages: format_messages(messages),
          functions: functions,
          function_call: { name: functions.first[:name] },
          temperature: options[:temperature] || 0.3
        }
      )

      parse_function_call_response(response)
    rescue StandardError => e
      Rails.logger.error("OpenAI structured output error: #{e.message}")
      raise
    end

    private

    def format_messages(messages)
      messages.map do |msg|
        {
          role: msg[:role] || msg["role"],
          content: msg[:content] || msg["content"]
        }
      end
    end

    def parse_function_call_response(response)
      message = response.dig("choices", 0, "message")
      function_call = message["function_call"]

      return default_response unless function_call

      {
        intent: function_call["name"],
        parameters: JSON.parse(function_call["arguments"] || "{}"),
        confidence: 0.9 # OpenAI function calling is deterministic
      }
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse function call arguments: #{e.message}")
      default_response
    end

    def default_response
      {
        intent: "general_chat",
        parameters: {},
        confidence: 0.5
      }
    end
  end
end
