# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module AIProviders
  class GeminiProvider < BaseProvider
    API_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

    def initialize(api_key:, model:)
      @api_key = api_key
      @model_name = model
    end

    def chat_completion(messages, options = {})
      # Convert messages to Gemini format, extracting system instruction
      system_instruction, gemini_messages = format_messages_for_gemini(messages)

      # Build request body
      generation_config = { temperature: options[:temperature] || 0.7, }
      generation_config[:maxOutputTokens] = options[:max_tokens] if options[:max_tokens]

      response_format = options.delete(:response_format) || :json
      generation_config[:responseMimeType] = Mime[response_format].to_s

      request_body = {
        contents: gemini_messages,
        generationConfig: generation_config
      }

      # Add system instruction if present
      if system_instruction.present?
        request_body[:systemInstruction] = {
          role: "system",
          parts: [{ text: system_instruction }]
        }
      end

      puts "=" * 80
      puts "GEMINI REQUEST BODY"
      puts request_body.to_json
      puts "=" * 80
      response = make_api_request("generateContent", request_body)
      extract_text_from_response(response)
    rescue StandardError => e
      Rails.logger.error("Gemini API error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise
    end

    # Structured output using Gemini function calling API
    # @param structured_prompt [Hash] Hash with :messages and :functions (function declarations)
    # @param options [Hash] Additional options
    # @option options [Boolean] :allow_multiple Whether to allow multiple function calls (default: false)
    # @option options [Float] :temperature Temperature for generation (default: 0.3)
    # @return [Hash, Array<Hash>] Single hash with :name and :parameters, or array of hashes if allow_multiple is true
    def structured_output(structured_prompt, options = {})
      puts structured_prompt.inspect
      allow_multiple = options[:allow_multiple] || false

      # Convert messages to Gemini format, extracting system instruction
      system_instruction, gemini_messages = format_messages_for_gemini(structured_prompt[:messages])

      # Build request body with function calling
      request_body = {
        contents: gemini_messages,
        tools: [
          {
            functionDeclarations: structured_prompt[:functions]
          }
        ],
        generationConfig: {
          temperature: options[:temperature] || 0.7,
        }
      }
      request_body[:generationConfig][:maxOutputTokens] = options[:max_tokens] if options[:max_tokens]

      # Add system instruction if present
      if system_instruction.present?
        request_body[:systemInstruction] = {
          parts: [{ text: system_instruction }]
        }
      end

      if allow_multiple
        request_body[:toolConfig] = {
          functionCallingConfig: {
            mode: "any"
          }
        }
      end

      response = make_api_request("generateContent", request_body)
      {
        text: extract_text_from_response(response),
        tools: parse_function_call_response(response)
      }
    rescue StandardError => e
      Rails.logger.error("Gemini structured output error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise
    end

    private

    def make_api_request(method, request_body)
      uri = URI("#{API_BASE_URL}/models/#{@model_name}:#{method}?key=#{@api_key}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request.body = request_body.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        error_message = "Gemini API error: #{response.code} #{response.message}"
        begin
          error_body = JSON.parse(response.body)
          error_message += " - #{error_body['error']&.dig('message') || response.body}"
        rescue JSON::ParserError
          error_message += " - #{response.body}"
        end
        Rails.logger.error(error_message)
        raise StandardError, error_message
      end

      JSON.parse(response.body)
    end

    def extract_text_from_response(response)
      response.dig("candidates", 0, "content", "parts", 0, "text") || ""
    end

    # Parse function call response from Gemini API
    # @param response [Hash] The API response
    # @return [Hash, Array<Hash>] Function call(s) with :name and :parameters
    def parse_function_call_response(response)
      candidates = response.dig("candidates")
      return unless candidates&.any?

      content = candidates[0].dig("content")
      return unless content

      parts = content.dig("parts")
      return unless parts&.any?

      # Extract all function calls from parts
      function_calls = parts.filter_map do |part|
        function_call = part["functionCall"]
        next unless function_call

        {
          name: function_call["name"],
          parameters: function_call["args"]&.deep_symbolize_keys || {}
        }
      end

      return if function_calls.empty?

      function_calls
    end

    # Convert messages from standard format to Gemini format
    # Standard: { role: "user/assistant/system", content: "..." }
    # Gemini: { role: "user/model", parts: [{ text: "..." }] }
    # @return [Array<String, Array>] [system_instruction, gemini_messages]
    def format_messages_for_gemini(messages)
      system_instruction = []
      gemini_messages = []

      messages.each do |msg|
        case msg[:role]
        when "system"
          system_instruction << msg[:content]
        when "function"
          case msg[:action]
          when "call"
            gemini_messages << { role: "model", parts: msg[:parts] }
          when "response"
            gemini_messages << { role: "function", parts: msg[:parts] }
          end
        when "assistant"
          gemini_messages << { role: "model", parts: [{ text: msg[:content] }] }
        else
          gemini_messages << { role: "user", parts: [{ text: msg[:content] }] }
        end
      end

      [system_instruction.compact.join("\n\n").presence, gemini_messages]
    end
  end
end
