# frozen_string_literal: true

module Slack
  # Reads Slack API message responses and extracts all text content recursively
  class MessageReader
    class << self
      def read(message)
        return message if message.is_a?(String)

        texts = extract_texts(message)
        texts.reject(&:empty?).join("\n")
      end

      private

      # Recursively extract all text values from a Slack message structure
      # @param obj [Object] The object to extract texts from
      # @return [Array<String>] Array of extracted text strings
      def extract_texts(obj)
        texts = []

        case obj
        when Hash
          if obj.key?(:text)
            text_value = obj[:text]
            if text_value.is_a?(String)
              texts << text_value
            elsif text_value.is_a?(Hash)
              inner_text = text_value[:text]
              texts << inner_text if inner_text.is_a?(String)
              obj.each do |key, value|
                next if key.to_sym == :text
                texts.concat(extract_texts(value))
              end
              return texts
            end
          end

          obj.each do |key, value|
            next if key.to_sym == :text
            texts.concat(extract_texts(value))
          end

        when Array
          obj.each { |element| texts.concat(extract_texts(element)) }
        else
          nil
        end

        texts
      end
    end
  end
end
