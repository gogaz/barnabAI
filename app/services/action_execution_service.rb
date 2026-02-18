# frozen_string_literal: true

class ActionExecutionService
  def initialize(user, context:)
    @user = user
    @context = context
    @github_service = Github::Client.new(user)
    @ai_provider = AIProviderFactory.create(user)
  end

  # @return [Array<Slack::MessageBuilder>] Array of message builders to send
  def execute(intent, parameters)
    # @type Actions::BaseAction
    action_class = action_class_for(intent)
    return [Slack::MessageBuilder.new(text: "Unknown intent: #{intent}")] unless action_class

    action = action_class.new(
      @user,
      github_client: @github_service,
      ai_provider: @ai_provider,
      context: @context
    )
    Array.wrap(action.execute(parameters))
  end

  private

  def action_class_for(intent)
    Actions::BaseAction.descendants.find do |klass|
      klass.function_code == intent
    end
  end
end
