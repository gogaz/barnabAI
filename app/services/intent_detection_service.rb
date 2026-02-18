# frozen_string_literal: true

class IntentDetectionService
  # List of action classes that can be detected as intents
  INTENT_ACTIONS = [
    Actions::SummarizeMyCurrentWorkAction,
    Actions::SinglePullRequestStatusUpdateAction,
    Actions::UpdatePullRequestAction,
    Actions::ListPrsByTeamsAction,
  ].freeze

  def initialize(ai_provider)
    @ai_provider = ai_provider
  end

  def detect_intent(context)
    structured_prompt = context.build_structured_prompt(functions: INTENT_ACTIONS)
    result = @ai_provider.structured_output(structured_prompt)

    intent = result[:intent]
    parameters = result[:parameters] || {}

    context.add_assistant_message("Detected intent #{intent} with parameters #{parameters.inspect}")

    {
      intent: intent,
      parameters: parameters,
    }
  rescue StandardError => e
    Rails.logger.error("Intent detection failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    default_response
  end

  private

  def default_response
    {
      intent: "general_chat",
      parameters: {},
    }
  end
end
