# frozen_string_literal: true

module Formatters
  class SlackMessageFormatter
    # Format a response message for Slack, handling both text and blocks
    def self.format_message_options(response_message)
      message_options = {}
      
      # Try to parse as JSON blocks, if it's valid JSON array, treat as blocks
      if response_message.is_a?(String) && response_message.strip.start_with?("[") && response_message.strip.end_with?("]")
        begin
          parsed_blocks = JSON.parse(response_message)
          if parsed_blocks.is_a?(Array)
            message_options[:blocks] = response_message
            # Determine fallback text based on intent or content
            fallback_text = if parsed_blocks.first&.dig("type") == "header" || parsed_blocks.any? { |b| b["type"] == "section" && b.dig("text", "text")&.include?("PR") }
              "PR Summary"
            else
              "Summary"
            end
            message_options[:text] = fallback_text
          else
            message_options[:text] = response_message
          end
        rescue JSON::ParserError
          # Not valid JSON, treat as plain text
          message_options[:text] = response_message
        end
      else
        message_options[:text] = response_message.is_a?(Hash) ? response_message[:message] : response_message
      end
      
      message_options
    end
  end
end
