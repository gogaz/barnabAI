# frozen_string_literal: true

class SuccessfulGithubOauthJob < ApplicationJob
  queue_as :default

  def perform(github_token_id:)
    github_token = GithubToken.find_by(id: github_token_id)
    return unless github_token

    user = github_token.user
    github_user_info = get_github_user_info(github_token.token)
    github_username = github_user_info["login"]

    github_token.update!(
      github_user_id: github_user_info["id"].to_s,
      github_username: github_user_info["login"],
      github_email: github_user_info["email"]
    )

    slack_user_info = Slack::Client.get_user_info(user_id: user.slack_user_id)
    user.update!(
      slack_username: slack_user_info[:name],
      slack_display_name: slack_user_info[:display_name],
      slack_email: slack_user_info[:email]
    )

    UserMapping.find_or_initialize_by(user_id: user.id) do |mapping|
      mapping.slack_user_id = user.slack_user_id
      mapping.github_username = github_username
      mapping.slack_username = slack_user_info[:name]
      mapping.save!
    end

    Slack::Client.send_message(
      channel: user.slack_user_id,
      text: "🎉 Your GitHub account *#{github_username}* has been successfully connected!"
    )
  rescue StandardError => e
    Rails.logger.error("SuccessfulGithubOauthJob failed: #{e.message}")
    Rails.logger.error(e.backtrace&.join("\n"))
    raise e
  end

  private

  def get_github_user_info(access_token)
    uri = URI("https://api.github.com/user")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "token #{access_token}"
    request["Accept"] = "application/vnd.github.v3+json"

    response = http.request(request)
    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("Failed to get GitHub user info: #{e.message}")
    Rails.logger.error(e.backtrace&.join("\n"))
    {}
  end
end


