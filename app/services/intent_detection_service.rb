# frozen_string_literal: true

class IntentDetectionService
  INTENT_SCHEMA = {
    function_name: "detect_intent",
    description: "Detect the user's intent from their message. Determine what action they want to perform on a GitHub pull request.",
    parameters: {
      type: "object",
      properties: {
        intent: {
          type: "string",
          enum: [
            "merge_pr",
            "comment_on_pr",
            "get_pr_info",
            "create_pr",
            "run_specs",
            "get_pr_files",
            "approve_pr",
            "general_chat"
          ],
          description: "The detected intent from the user's message"
        },
        parameters: {
          type: "object",
          properties: {
            message: {
              type: "string",
              description: "The message content for comment_on_pr intent"
            },
            pr_number: {
              type: "integer",
              description: "The PR number (if mentioned or in context)"
            },
            branch_name: {
              type: "string",
              description: "The branch name for create_pr intent"
            },
            base_branch: {
              type: "string",
              description: "The base branch for create_pr intent (default: main)"
            },
            title: {
              type: "string",
              description: "The PR title for create_pr intent"
            },
            workflow_file: {
              type: "string",
              description: "The workflow file name for run_specs intent"
            }
          }
        },
        confidence: {
          type: "number",
          minimum: 0,
          maximum: 1,
          description: "Confidence level of the intent detection (0.0 to 1.0)"
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
    default_response
  end

  private

  def build_messages(user_message, context)
    system_message = build_system_message(context)
    user_message_content = build_user_message(user_message, context)

    [
      { role: "system", content: system_message },
      { role: "user", content: user_message_content }
    ]
  end

  def build_system_message(context)
    pr_context = if context[:pull_request]
      pr = context[:pull_request]
      "Current PR context:\n" \
      "- PR ##{pr.number}: #{pr.title}\n" \
      "- State: #{pr.state}\n" \
      "- Author: #{pr.author}\n" \
      "- Repository: #{pr.repository.full_name}\n"
    else
      "No PR context available. User may be asking about a different PR or general question.\n"
    end

    "You are an intent detection system for a GitHub PR management bot. " \
    "Analyze the user's message and determine their intent. " \
    "Available intents: merge_pr, comment_on_pr, get_pr_info, create_pr, run_specs, get_pr_files, approve_pr, general_chat.\n\n" \
    "#{pr_context}\n" \
    "Return the detected intent with appropriate parameters."
  end

  def build_user_message(user_message, context)
    message = "User message: #{user_message}\n"

    if context[:pull_request]
      message += "\nThe user is currently viewing or discussing PR ##{context[:pull_request].number}."
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
    {
      message: normalized[:message] || normalized["message"],
      pr_number: normalized[:pr_number] || normalized["pr_number"],
      branch_name: normalized[:branch_name] || normalized["branch_name"],
      base_branch: normalized[:base_branch] || normalized["base_branch"],
      title: normalized[:title] || normalized["title"],
      workflow_file: normalized[:workflow_file] || normalized["workflow_file"]
    }.compact
  end

  def default_response
    {
      intent: "general_chat",
      parameters: {},
      confidence: 0.5
    }
  end
end
