# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module AIProviders
  class GeminiProvider < BaseProvider
    API_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

    def initialize(api_key:, model: "gemini-pro")
      @api_key = api_key
      @model_name = model
    end

    def chat_completion(messages, options = {})
      # Convert messages to Gemini format
      contents = format_messages_for_gemini(messages)

      # Build request body
      request_body = {
        contents: contents,
        generationConfig: {
          temperature: options[:temperature] || 0.7,
          maxOutputTokens: options[:max_tokens] || 1000
        }
      }

      response = make_api_request("generateContent", request_body)
      extract_text_from_response(response)
    rescue StandardError => e
      Rails.logger.error("Gemini API error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise
    end

    def structured_output(messages, schema, options = {})
      # Build system message for structured output
      system_message = build_system_message_for_structured_output(schema)

      # Format user messages
      user_content = format_user_messages(messages)

      # Combine system message with user content
      prompt = "#{system_message}\n\nUser message:\n#{user_content}\n\nRespond with JSON only:"

      # Build request body
      request_body = {
        contents: [
          {
            parts: [
              { text: prompt }
            ]
          }
        ],
        generationConfig: {
          temperature: options[:temperature] || 0.3,
          responseMimeType: "application/json"
        }
      }

      response = make_api_request("generateContent", request_body)
      text = extract_text_from_response(response)
      parse_structured_response(text, schema)
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

    def format_messages_for_gemini(messages)
      messages.map do |msg|
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]

        # Gemini uses "user" and "model" roles (not "assistant")
        gemini_role = role == "assistant" ? "model" : "user"

        {
          role: gemini_role,
          parts: [
            { text: content }
          ]
        }
      end
    end

    def format_user_messages(messages)
      messages.map do |msg|
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]
        "#{role.capitalize}: #{content}"
      end.join("\n")
    end

    def extract_text_from_response(response)
      candidates = response.dig("candidates")
      return "" unless candidates&.any?

      content = candidates[0].dig("content")
      return "" unless content

      parts = content.dig("parts")
      return "" unless parts&.any?

      parts[0].dig("text") || ""
    end

    def build_system_message_for_structured_output(schema)
      function_name = schema[:function_name] || "detect_intent"
      description = schema[:description] || "Detect user intent from the conversation"
      parameters = schema[:parameters] || {}

      <<~PROMPT
        You are an intent detection system. Analyze the user's message and return a JSON response with the following structure:

        {
          "intent": "#{function_name}",
          "parameters": #{parameters.to_json}
        }

        #{description}

        Return only valid JSON, no additional text or explanation.
      PROMPT
    end

    def parse_structured_response(text, schema)
      return default_response unless text

      # Extract JSON from response (might have markdown code blocks)
      json_text = text.strip
      json_text = json_text.gsub(/^```json\s*/, "").gsub(/^```\s*/, "").gsub(/\s*```$/, "").strip

      parsed = JSON.parse(json_text)
      {
        intent: parsed["intent"] || schema[:function_name] || "general_chat",
        parameters: parsed["parameters"] || {},
        confidence: 0.9
      }
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse Gemini structured response: #{e.message}")
      Rails.logger.error("Response text: #{text}")
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
