# frozen_string_literal: true

class SlackOauthController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:callback]

  # Landing page for Slack app installation
  def install
    # Render the installation page
  end

  # Redirect user to Slack OAuth authorization page
  def authorize
    client_id = ENV.fetch("SLACK_CLIENT_ID")
    redirect_uri = slack_oauth_callback_url
    scope = "app_mentions:read,chat:write,channels:read,groups:read,im:read,im:write,users:read"
    state = SecureRandom.hex(16)

    # Store state in session for verification
    session[:slack_oauth_state] = state

    oauth_url = "https://slack.com/oauth/v2/authorize?" \
                "client_id=#{client_id}&" \
                "scope=#{CGI.escape(scope)}&" \
                "redirect_uri=#{CGI.escape(redirect_uri)}&" \
                "state=#{state}"

    redirect_to oauth_url, allow_other_host: true
  end

  # Handle OAuth callback from Slack
  def callback
    # Verify state parameter
    if params[:state] != session[:slack_oauth_state]
      redirect_to root_path, alert: "Invalid state parameter. Please try again."
      return
    end

    # Check for errors
    if params[:error]
      redirect_to root_path, alert: "Slack authorization failed: #{params[:error]}"
      return
    end

    # Exchange code for access token
    code = params[:code]
    result = exchange_code_for_token(code)

    if result[:success]
      # Save or update Slack installation
      installation = save_slack_installation(result)

      # Clear state from session
      session.delete(:slack_oauth_state)

      redirect_to slack_oauth_success_path,
                  notice: "Successfully installed Slack app in workspace: #{installation.team_name}!"
    else
      redirect_to root_path, alert: "Failed to connect: #{result[:error]}"
    end
  end

  # Success page after installation
  def success
    # Render success page
  end

  private

  def exchange_code_for_token(code)
    client_id = ENV.fetch("SLACK_CLIENT_ID")
    client_secret = ENV.fetch("SLACK_CLIENT_SECRET")
    redirect_uri = slack_oauth_callback_url

    uri = URI("https://slack.com/api/oauth.v2.access")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request.set_form_data(
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      redirect_uri: redirect_uri
    )

    response = http.request(request)
    data = JSON.parse(response.body)

    if data["ok"]
      {
        success: true,
        access_token: data.dig("authed_user", "access_token"),
        bot_token: data.dig("access_token"),
        team: data.dig("team"),
        bot_user_id: data.dig("bot_user_id"),
        scope: data.dig("scope"),
        installing_user_id: data.dig("authed_user", "id")
      }
    else
      {
        success: false,
        error: data["error"] || "Unknown error"
      }
    end
  rescue StandardError => e
    {
      success: false,
      error: e.message
    }
  end

  def save_slack_installation(result)
    team_id = result[:team]["id"]
    installation = SlackInstallation.find_or_initialize_by(team_id: team_id)

    installation.assign_attributes(
      team_name: result[:team]["name"],
      bot_token: result[:bot_token],
      access_token: result[:access_token],
      bot_user_id: result[:bot_user_id],
      bot_scope: result[:scope],
      installing_user_id: result[:installing_user_id],
      installed_at: Time.current
    )

    installation.save!
    installation
  end
end
