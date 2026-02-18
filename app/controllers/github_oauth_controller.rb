# frozen_string_literal: true

class GithubOauthController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:callback]

  # Landing page for GitHub OAuth installation
  def index
  end

  # Redirect user to GitHub OAuth authorization page
  def authorize
    client_id = ENV.fetch("GITHUB_CLIENT_ID")
    redirect_uri = github_oauth_callback_url
    scope = "repo,read:user,read:org"
    state = SecureRandom.hex(16)
    
    # Store state in session for verification
    session[:github_oauth_state] = state
    # Store slack_user_id for per-user authentication
    session[:github_oauth_slack_user_id] = params[:slack_user_id] if params[:slack_user_id]

    oauth_params = {
      "client_id" => client_id,
      "scope" => scope,
      "redirect_uri" => redirect_uri,
      "state" => state
    }
    
    # If force=true, add prompt=consent to force GitHub to re-ask for permissions
    # This is necessary to get updated scopes (like read:org) if they weren't granted initially
    if params[:force] == "true"
      oauth_params["prompt"] = "consent"
    end

    oauth_url = "https://github.com/login/oauth/authorize?#{URI.encode_www_form(oauth_params)}"

    redirect_to oauth_url, allow_other_host: true
  end

  # Handle OAuth callback from GitHub
  def callback
    # Verify state parameter
    if params[:state] != session[:github_oauth_state]
      redirect_to root_path, alert: "Invalid state parameter. Please try again."
      return
    end

    # Check for errors
    if params[:error]
      redirect_to root_path, alert: "GitHub authorization failed: #{params[:error]}"
      return
    end

    # Exchange code for access token
    code = params[:code]
    result = exchange_code_for_token(code)

    if result[:success]
      slack_user_id = session[:github_oauth_slack_user_id]

      if slack_user_id
        # Save minimal token info - job will fetch full user details
        github_token = save_user_github_token(slack_user_id, result[:access_token], result[:scope])

        SuccessfulGithubOauthJob.perform_later(github_token_id: github_token.id)
      end
      
      # Clear state from session
      session.delete(:github_oauth_state)
      session.delete(:github_oauth_slack_user_id)

      redirect_to github_oauth_success_path
    else
      redirect_to root_path, alert: "Failed to connect: #{result[:error]}"
    end
  end

  # Success page after installation
  def success
  end

  private

  def exchange_code_for_token(code)
    client_id = ENV.fetch("GITHUB_CLIENT_ID")
    client_secret = ENV.fetch("GITHUB_CLIENT_SECRET")
    redirect_uri = github_oauth_callback_url

    uri = URI("https://github.com/login/oauth/access_token")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Accept"] = "application/json"
    request.set_form_data(
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      redirect_uri: redirect_uri
    )

    response = http.request(request)
    data = JSON.parse(response.body)

    if data["access_token"]
      {
        success: true,
        access_token: data["access_token"],
        scope: data["scope"],
        token_type: data["token_type"]
      }
    else
      {
        success: false,
        error: data["error"] || data["error_description"] || "Unknown error"
      }
    end
  rescue StandardError => e
    {
      success: false,
      error: e.message
    }
  end

  def save_user_github_token(slack_user_id, access_token, scope = nil)
    ApplicationRecord.transaction do
      user = User.find_or_create_by!(slack_user_id: slack_user_id)

      github_token = GithubToken.find_or_initialize_by(user: user)

      # Use the actual scope returned by GitHub, or fallback to default
      actual_scope = scope || "repo,read:user,read:org"

      github_token.assign_attributes(
        token: access_token,
        scope: actual_scope,
        connected_at: Time.current
      )

      github_token.save!

      github_token
    end
  end
end
