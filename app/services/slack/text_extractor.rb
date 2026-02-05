# frozen_string_literal: true

module Slack
  class TextExtractor
    # Extract text content from Slack Block Kit blocks
    def self.extract_text_from_slack_blocks(blocks)
      return "" unless blocks.is_a?(Array)
      
      text_parts = []
      blocks.each do |block|
        block_type = block["type"] || block[:type]
        
        case block_type
        when "section"
          # Section blocks can have text or fields
          if block["text"]
            extracted = extract_text_from_block_element(block["text"])
            text_parts << extracted if extracted.present?
          end
          if block["fields"]
            block["fields"].each do |field|
              extracted = extract_text_from_block_element(field)
              text_parts << extracted if extracted.present?
            end
          end
        when "header"
          if block["text"]
            extracted = extract_text_from_block_element(block["text"])
            text_parts << extracted if extracted.present?
          end
        when "context"
          if block["elements"]
            block["elements"].each do |element|
              extracted = extract_text_from_block_element(element)
              text_parts << extracted if extracted.present?
            end
          end
        when "divider"
          # No text in dividers
        when "rich_text"
          # Rich text blocks have elements array
          if block["elements"]
            block["elements"].each do |element|
              extracted = extract_text_from_rich_text_element(element)
              text_parts << extracted if extracted.present?
            end
          end
        else
          # For other block types, try to find text field
          if block["text"]
            extracted = extract_text_from_block_element(block["text"])
            text_parts << extracted if extracted.present?
          end
        end
      end
      
      text_parts.compact.join("\n").strip
    end
    
    # Extract text from rich text elements (used in rich_text blocks)
    def self.extract_text_from_rich_text_element(element)
      return "" unless element.is_a?(Hash)
      
      element_type = element["type"] || element[:type]
      case element_type
      when "text"
        text = element["text"] || element[:text] || ""
        # Extract URLs from markdown if present
        extract_urls_from_markdown(text)
      when "link"
        # Rich text link element: has url and text
        url = element["url"] || element[:url] || ""
        link_text = element["text"] || element[:text] || ""
        
        if link_text.present? && link_text != url
          "#{link_text} (#{url})"
        else
          url
        end
      when "rich_text_section"
        if element["elements"]
          element["elements"].map { |e| extract_text_from_rich_text_element(e) }.join("")
        else
          ""
        end
      when "rich_text_list"
        if element["elements"]
          element["elements"].map { |e| extract_text_from_rich_text_element(e) }.join("\n")
        else
          ""
        end
      else
        # For other rich text element types, try to find text
        text = element["text"] || element[:text] || ""
        extract_urls_from_markdown(text)
      end
    end

    def self.extract_text_from_block_element(element)
      return "" unless element
      
      if element.is_a?(Hash)
        # Slack Block Kit text elements have structure: { "type": "mrkdwn", "text": "actual text" }
        # So we need to check for the "text" key which contains the actual text content
        text = element["text"] || element[:text]
        
        # If text is itself an object (nested structure), recurse
        if text.is_a?(Hash)
          text_content = text["text"] || text[:text] || ""
        else
          text_content = text || ""
        end
        
        # Extract URLs from markdown links in the text
        # Slack markdown format: <url|text> or <url>
        # We want to include both the text and the URL
        text_with_urls = extract_urls_from_markdown(text_content)
        
        text_with_urls
      else
        element.to_s
      end
    end
    
    # Extract URLs from Slack markdown format and include them in the text
    # Format: <url|text> or <url>
    # Returns: "text (url)" or "url" if no text
    def self.extract_urls_from_markdown(text)
      return "" unless text.is_a?(String)
      
      # Pattern to match Slack markdown links: <url|text> or <url>
      # This regex captures:
      # - Group 1: URL (everything before | or >)
      # - Group 2: Text (optional, everything between | and >)
      text.gsub(/<([^|>]+)(?:\|([^>]+))?>/) do |match|
        url = $1
        link_text = $2
        
        if link_text && link_text != url
          # Both text and URL: include both
          "#{link_text} (#{url})"
        else
          # Only URL: just return the URL
          url
        end
      end
    end
  end
end
