# frozen_string_literal: true

module Formatters
  class ResponseFormatter
    # Format a success response based on intent type
    def self.format_success(intent, result)
      message = result[:message] || "Action completed successfully."

      # Add additional details if available
      if result[:data] && intent == "get_pr_info"
        pr_data = result[:data][:pr]
        message += "\n\n" \
                   "PR ##{pr_data[:number]}: #{pr_data[:title]}\n" \
                   "State: #{pr_data[:state]}\n" \
                   "Author: #{pr_data[:author]}\n" \
                   "Comments: #{result[:data][:comments_count]}\n" \
                   "Files changed: #{result[:data][:files_count]}"
      elsif intent == "list_prs_by_teams" && result[:data] && result[:data][:blocks]
        # Return blocks directly if available (AI-generated summary)
        return result[:data][:blocks]
      elsif intent == "list_prs_by_teams" && result[:data] && result[:data][:prs]
        # Fallback to text format if blocks not available
        prs = result[:data][:prs]
        teams = result[:data][:teams] || []
        message = "Found #{prs.count} PR(s) impacting team(s): #{teams.join(', ')}\n\n"
        prs.each do |pr|
          message += "• ##{pr[:number]}: #{pr[:title]} (#{pr[:state]})\n"
          message += "  Repository: #{pr[:repository]}\n"
          message += "  Impacted teams: #{pr[:impacted_teams]&.join(', ') || 'None'}\n"
          message += "  URL: #{pr[:url]}\n"
          message += "  Created: #{pr[:created_at]}\n\n"
        end
      end

      message
    end

    # Format an error response
    def self.format_error(result)
      result[:message] || "Failed to execute action."
    end
  end
end
