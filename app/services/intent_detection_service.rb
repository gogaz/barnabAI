# frozen_string_literal: true

class IntentDetectionService
  INTENT_SCHEMA = {
    function_name: "detect_intent",
    description: "Detect the user's intent from their message. If you are unsure about the intent, use 'ask_clarification' and provide a clarifying question.",
    parameters: {
      type: "object",
      properties: {
        intent: {
          type: "string",
          enum: [
            "SUMMARIZE_EXISTING_PRS",
            "pull_request_details_summary",
            "start_pull_request_workflow",
            "list_prs_by_teams",
            "ask_clarification",
            "general_chat"
          ],
          description: "The detected intent from the user's message. Use 'ask_clarification' if the intent is unclear."
        },
        parameters: {
          type: "object",
          properties: {
            clarification_question: {
              type: "string",
              description: "A clarifying question to ask the user when intent is 'ask_clarification'"
            },
            response: {
              type: "string",
              description: "When intent is 'general_chat', provide a helpful response to the user's message directly. This will save an additional API call. Be concise and helpful."
            },
            pr_number: {
              type: "integer",
              description: "When intent is 'pull_request_details_summary' or 'start_pull_request_workflow', extract the PR number from the user's message. If the user mentions a PR number (e.g., 'PR #123', '#123', 'PR 123'), include it here. If no PR number is mentioned but there's a PR context, use that PR number. Required when intent is 'pull_request_details_summary' or 'start_pull_request_workflow'."
            },
            repository: {
              type: "string",
              description: "When intent is 'pull_request_details_summary' or 'start_pull_request_workflow', extract the repository from the user's message (format: 'owner/repo-name'). If the user mentions a repository, include it here. If no repository is mentioned but there's a PR context, use that repository. Required when intent is 'pull_request_details_summary' or 'start_pull_request_workflow' and there's no PR context."
            },
            teams: {
              oneOf: [
                {
                  type: "string",
                  description: "When intent is 'list_prs_by_teams', extract a single team name from the user's message (e.g., '@matera-tech/rentalbatros' or 'rentalbatros'). Only include if user mentions a single team."
                },
                {
                  type: "array",
                  items: {
                    type: "string"
                  },
                  description: "When intent is 'list_prs_by_teams', extract multiple team names from the user's message (e.g., ['@matera-tech/rentalbatros', '@matera-tech/probiotics']). Only include if user mentions multiple teams."
                }
              ],
              description: "When intent is 'list_prs_by_teams', extract the team name(s) from the user's message. Teams can be mentioned with or without the @ prefix (e.g., 'rentalbatros' or '@matera-tech/rentalbatros'). Required when intent is 'list_prs_by_teams'."
            },
            days: {
              type: "integer",
              description: "When intent is 'list_prs_by_teams', extract the number of days to look back for PRs. Default is 7 days if not specified. Examples: 'last 3 days' -> 3, 'past week' -> 7, 'last month' -> 30, '2 weeks' -> 14. Only include if user explicitly mentions a duration."
            },
            filters: {
              type: "object",
              properties: {
                state: {
                  type: "string",
                  enum: ["open", "closed", "merged"],
                  description: "Filter PRs by state (open, closed, merged). Default: open"
                },
                repository: {
                  oneOf: [
                    {
                      type: "string",
                      description: "Filter PRs by a single repository (format: owner/repo-name). Only include if user specifically mentions a repository."
                    },
                    {
                      type: "array",
                      items: {
                        type: "string"
                      },
                      description: "Filter PRs by multiple repositories (format: owner/repo-name). Only include if user specifically mentions multiple repositories."
                    }
                  ],
                  description: "Filter PRs by repository or repositories. Can be a single repository (string) or multiple repositories (array of strings). Only include if user specifically mentions repositories."
                },
                label: {
                  type: "string",
                  description: "Filter PRs by label. Only include if user specifically mentions a label."
                },
                assignee: {
                  type: "string",
                  description: "Filter PRs by assignee username. Only include if user specifically mentions an assignee."
                },
                review_status: {
                  type: "string",
                  enum: ["approved", "changes_requested", "commented", "none"],
                  description: "Filter PRs by review status. Only include if user specifically mentions review status."
                }
              },
              description: "Optional filters to apply to the PR search. Only include filters that the user explicitly mentions in their request."
            }
          }
        },
        confidence: {
          type: "number",
          minimum: 0,
          maximum: 1,
          description: "Confidence level of the intent detection (0.0 to 1.0). Use low confidence (< 0.7) when asking for clarification."
        }
      },
      required: ["intent", "parameters", "confidence"]
    }
  }.freeze

  def initialize(ai_provider)
    @ai_provider = ai_provider
  end

  def detect_intent(user_message, context = {})
    messages = build_messages(user_message, context)
    result = @ai_provider.structured_output(messages, INTENT_SCHEMA)
    normalize_result(result)
  rescue StandardError => e
    Rails.logger.error("Intent detection failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    default_response
  end

  private

  def build_messages(user_message, context)
    system_message = build_system_message(context)
    messages = [{ role: "system", content: system_message }]

    # Add thread messages as context if available (only in threads, not DMs)
    thread_messages = context[:thread_messages] || []
    if thread_messages.any?
      Rails.logger.info("Including #{thread_messages.count} thread messages in intent detection context")
      
      # Add thread messages as user/assistant messages for context
      # Exclude the current message (it will be added at the end)
      thread_messages.each do |thread_msg|
        msg_text = thread_msg[:text] || thread_msg["text"]
        is_bot = thread_msg[:is_bot] || thread_msg["is_bot"] || false
        
        # Skip if empty
        next if msg_text.blank?
        
        # Determine role: bot messages are "assistant", user messages are "user"
        role = is_bot ? "assistant" : "user"
        
        messages << {
          role: role,
          content: msg_text
        }
      end
    end

    # Add conversation context for direct messages (DMs)
    # Only include if we're not in a thread (no thread_messages) and conversation exists
    conversation_messages = context[:conversation] || []
    if conversation_messages.any? && thread_messages.empty?
      Rails.logger.info("Including #{conversation_messages.count} conversation messages in intent detection context (DM)")
      
      conversation_messages.each do |conv_msg|
        role = conv_msg[:role] || conv_msg["role"]
        content = conv_msg[:content] || conv_msg["content"]
        
        # Skip if empty
        next if content.blank?
        
        # Map "assistant" to "assistant" and "user" to "user"
        messages << {
          role: role == "assistant" ? "assistant" : "user",
          content: content
        }
      end
    end

    # Add the current user message
    user_message_content = build_user_message(user_message, context)
    messages << { role: "user", content: user_message_content }

    messages
  end

  def build_system_message(context)
    pr_context = if context[:pull_request]
      pr = context[:pull_request]
      "Current PR context:\n" \
      "- PR ##{pr[:number]}: #{pr[:title]}\n" \
      "- State: #{pr[:state]}\n" \
      "- Author: #{pr[:author]}\n" \
      "- Repository: #{pr[:repository][:full_name]}\n"
    else
      ""
    end

    available_teams = context[:available_teams] || []
    available_teams_context = if available_teams.any?
      "Available teams for this workspace:\n#{available_teams.map { |t| "  - #{t}" }.join("\n")}\n\n" \
      "When extracting team names, match the user's input to one of these available teams. " \
      "Be flexible with typos and partial matches (e.g., 'rentalbatros' or 'rental' should match '@matera-tech/rentalbatros').\n\n"
    else
      ""
    end

    available_intents = [
      "SUMMARIZE_EXISTING_PRS - Summarize the user's ongoing pull requests",
      "pull_request_details_summary - Get a detailed summary of a specific PR including comments, reviews, and workflow status",
      "start_pull_request_workflow - Re-run a failed workflow for a pull request",
      "list_prs_by_teams - List all PRs that impact one or more specific teams (e.g., 'show PRs for rentalbatros', 'list PRs impacting @matera-tech/probiotics and @matera-tech/rentalbatros')"
    ].join("\n")

    pr_details_help = <<~HELP
      When the intent is 'pull_request_details_summary' or 'start_pull_request_workflow', you MUST extract:
      - PR number: Look for patterns in the user's message like 'PR #123', '#123', 'PR 123', 'pull request 123', etc.
        If no PR number is mentioned in the message, check if there's a PR context available. If there is, use that PR number.
        The 'pr_number' parameter is REQUIRED when intent is 'pull_request_details_summary' or 'start_pull_request_workflow'.
      - Repository: If the user mentions a repository (e.g., 'owner/repo-name', 'repo-name'), include it in the 'repository' parameter.
        If no repository is mentioned but there's a PR context available, use that repository.
        The 'repository' parameter is REQUIRED when intent is 'pull_request_details_summary' or 'start_pull_request_workflow' and there's no PR context.
      - If you cannot determine both PR number and repository, use 'ask_clarification' intent instead.
      
      When the intent is 'list_prs_by_teams', you MUST extract:
      - Teams: Extract team name(s) from the user's message and match them to the available teams list provided below.
        Teams can be mentioned with or without the @ prefix (e.g., 'rentalbatros', '@matera-tech/rentalbatros').
        IMPORTANT: Match the user's input to the closest team name from the available teams list. Be flexible with typos and partial matches.
        Examples: If user says 'rentalbatros' or 'rental', match it to '@matera-tech/rentalbatros' from the available teams.
        The 'teams' parameter can be a single string or an array of strings. It is REQUIRED when intent is 'list_prs_by_teams'.
        If the user mentions multiple teams, extract all of them as an array.
        Always use the exact team name from the available teams list (including the @ prefix if present).
        If you cannot determine the team(s) or match them to available teams, use 'ask_clarification' intent instead.
      - Days: Extract the number of days to look back for PRs. Default is 7 days if not specified.
        Examples: 'last 3 days' -> 3, 'past week' -> 7, 'last month' -> 30, '2 weeks' -> 14, 'past 10 days' -> 10.
        Only include the 'days' parameter if the user explicitly mentions a duration. If not mentioned, do not include it (default will be 7 days).
    HELP

    filters_help = <<~HELP
      When the intent is SUMMARIZE_EXISTING_PRS, you can add filters in the 'filters' parameter based on what the user asks for:
      - state: Filter by PR state (open, closed, merged). Default is 'open' if not specified.
      - repository: Filter by specific repository or repositories. Can be a single repository (string) or multiple repositories (array of strings). IMPORTANT: If the user mentions a repository name (even without owner), include it in the repository filter. The system will automatically find the correct owner/repo format.
      - label: Filter by label name. Only include if user mentions a specific label.
      - assignee: Filter by assignee username. Only include if user mentions a specific assignee.
      - review_status: Filter by review status (approved, changes_requested, commented, none). Only include if user mentions review status.
      
      CRITICAL: If the user mentions ANY repository name (like "api-core", "my-repo", etc.), you MUST include it in the repository filter, even if they don't specify the owner. The system will automatically resolve it.
    HELP

    "You are an intent detection system for a GitHub PR management bot. " \
    "Analyze the user's message and determine their intent.\n\n" \
    "Available intents:\n#{available_intents}\n\n" \
    "#{available_teams_context}" \
    "#{pr_details_help}\n\n" \
    "#{filters_help}\n\n" \
    "IMPORTANT: If you are unsure about the user's intent, use 'ask_clarification' and you MUST provide a helpful clarifying question in the 'clarification_question' parameter. " \
    "This question should directly ask the user for clarification. Be concise and helpful.\n\n" \
    "Only use 'SUMMARIZE_EXISTING_PRS' if you are confident the user wants to summarize their PRs.\n\n" \
    "When the intent is 'general_chat', you MUST provide a helpful response in the 'response' parameter. " \
    "This response should directly answer the user's question or engage in conversation. " \
    "Be concise, helpful, and context-aware.\n\n" \
    "#{pr_context}\n" \
    "Return the detected intent with appropriate parameters. Set confidence to a low value (< 0.7) when asking for clarification."
  end

  def build_user_message(user_message, context)
    message = "User message: #{user_message}\n"

    if context[:pull_request]
      message += "\nThe user is currently viewing or discussing PR ##{context[:pull_request][:number]}."
    end

    message
  end

  def normalize_result(result)
    {
      intent: result[:intent] || result["intent"] || "general_chat",
      parameters: normalize_parameters(result[:parameters] || result["parameters"] || {}),
      confidence: result[:confidence] || result["confidence"] || 0.5
    }
  end

  def normalize_parameters(params)
    normalized = params.is_a?(Hash) ? params : {}
    filters = normalized[:filters] || normalized["filters"] || {}
    
    # Normalize pr_number - convert to integer if present
    pr_number = normalized[:pr_number] || normalized["pr_number"]
    pr_number = pr_number.to_i if pr_number && pr_number.to_s.match?(/^\d+$/)
    
    # Normalize teams - ensure it's an array if present
    teams = normalized[:teams] || normalized["teams"]
    if teams
      teams = teams.is_a?(Array) ? teams : [teams]
    end
    
    # Normalize days - convert to integer if present
    days = normalized[:days] || normalized["days"]
    days = days.to_i if days && days.to_s.match?(/^\d+$/)
    
    result = {
      clarification_question: normalized[:clarification_question] || normalized["clarification_question"],
      response: normalized[:response] || normalized["response"],
      repository: normalized[:repository] || normalized["repository"],
      filters: filters.is_a?(Hash) ? filters : {}
    }
    
    # Include pr_number even if nil (so it's available for checking)
    result[:pr_number] = pr_number if pr_number
    
    # Include teams if present
    result[:teams] = teams if teams
    
    # Include days if present
    result[:days] = days if days
    
    result.compact
  end

  def default_response
    {
      intent: "general_chat",
      parameters: {},
      confidence: 0.5
    }
  end
end
