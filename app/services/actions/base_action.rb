# frozen_string_literal: true

class Actions::BaseAction
  def initialize(user, context:, ai_provider: nil)
    @user = user
    @github_client = Github::Client.new(user)
    @ai_provider = ai_provider || AIProviderFactory.create(user)
    @context = context
  end

  protected

  attr_reader :user, :github_client, :ai_provider, :context

  def require_pull_request!(parameters = {})
    pr_number = parameters[:pr_number]
    repository_param = parameters[:repository]

    return if pr_number.present? && repository_param.present?

    raise ArgumentError, "No pull request context found. Please try again with more context."
  end
end
