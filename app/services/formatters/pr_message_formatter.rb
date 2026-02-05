# frozen_string_literal: true

module Formatters
  class PrMessageFormatter
    # Format a PR message for Slack
    def self.format(pr)
      created_at = pr[:created_at]
      created_date = if created_at.respond_to?(:strftime)
        created_at.strftime("%Y-%m-%d")
      elsif created_at.is_a?(String)
        created_at
      else
        "unknown date"
      end
      
      # Format lines changed
      total_changes = pr[:total_changes] || (pr[:additions].to_i + pr[:deletions].to_i)
      lines_info = if total_changes > 0
        "+#{pr[:additions] || 0}/-#{pr[:deletions] || 0} (#{total_changes} total)"
      else
        "No changes"
      end
      
      pr_url = pr[:url] || "https://github.com/#{pr[:repository] || 'unknown/repo'}/pull/#{pr[:number]}"
      pr_title = pr[:title] || "PR ##{pr[:number]}"
      
      # Use Slack rich text format: title as link
      "<#{pr_url}|#{pr_title}>\n" \
      "Created: #{created_date} • Lines changed: #{lines_info}"
    end
  end
end
