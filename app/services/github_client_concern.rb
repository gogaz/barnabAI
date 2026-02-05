# frozen_string_literal: true

module GithubClientConcern
  extend ActiveSupport::Concern

  private

  def github_client(user)
    github_token = user.primary_github_token
    raise ArgumentError, "User has no GitHub token connected" unless github_token

    token = github_token.token
    raise ArgumentError, "GitHub token is invalid or expired" unless token

    require "octokit"
    Octokit::Client.new(access_token: token)
  end
end
