# frozen_string_literal: true

class Actions::BaseAction
  def initialize(user, pull_request: nil, slack_installation: nil, github_service: nil, ai_provider: nil)
    @user = user
    @pull_request = pull_request
    @slack_installation = slack_installation
    @github_service = github_service || GithubService.new(@user)
    @ai_provider = ai_provider || AIProviderFactory.create
  end

  protected

  attr_reader :user, :pull_request, :slack_installation, :github_service, :ai_provider
end
