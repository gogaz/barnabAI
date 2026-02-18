# frozen_string_literal: true

module Slack
  # See https://app.slack.com/block-kit-builder/ for reference on block structure and supported block types
  class MessageBuilder
    attr_accessor :text, :blocks

    # @param text [String] The text content of the message (optional - only used in notifications if blocks are provided)
    # @param blocks [Array<Hash>] An array of block objects representing the message
    def initialize(text: nil, blocks: [])
      @text = text
      @blocks = blocks || []
    end

    # @param text [String, Hash] The text content of the section block (string will be converted to mrkdwn format)
    # @param fields [String, Hash, Array<String|Hash>] An array of strings to be added as fields in the section block
    # @return [Slack::MessageBuilder] Returns self to allow chaining
    def add_section_block(text = nil, fields: nil)
      block = { type: "section" }
      if text
        block[:text] = text.is_a?(String) ? { type: "mrkdwn", text: text } : text
      end
      if fields
        block[:fields] = Array.wrap(fields).map do |field|
          field.is_a?(String) ? { type: "mrkdwn", text: field } : field
        end
      end
      @blocks << block
      self
    end

    # @param elements [String, Hash, Array<String|Hash>] A single string, hash, or an array of strings and/or hashes to be added as context elements
    # @return [Slack::MessageBuilder] Returns self to allow chaining
    def add_context_block(*elements)
      @blocks << {
        type: "context",
        elements: elements.map { |e| e.is_a?(String) ? { type: "mrkdwn", text: e } : e }
      }
      self
    end

    # @param title [String] Title of the section
    # @return [Slack::MessageBuilder] Returns self to allow chaining
    def add_header_block(title)
      @blocks << {
        type: "header",
        text: {
          type: "plain_text",
          text: title,
          emoji: true
        },
      }
      self
    end

    # Convert to hash for Slack API
    def to_h
      result = {}
      result[:text] = @text if @text.present?
      result[:blocks] = @blocks if @blocks.present?
      result
    end

    class << self
      # @return Hash{Symbol => String} A helper method to create a Slack image element for context blocks
      def block_image_element(image_url, alt_text)
        { type: "image", image_url: image_url, alt_text: alt_text }
      end
    end
  end
end
