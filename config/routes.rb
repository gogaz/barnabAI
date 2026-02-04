Rails.application.routes.draw do
  root "slack_oauth#install"
  
  # Slack OAuth routes
  get "/slack/oauth/install", to: "slack_oauth#install", as: :slack_oauth_install
  get "/slack/oauth/authorize", to: "slack_oauth#authorize", as: :slack_oauth_authorize
  get "/slack/oauth/callback", to: "slack_oauth#callback", as: :slack_oauth_callback
  get "/slack/oauth/success", to: "slack_oauth#success", as: :slack_oauth_success
  
  # Slack Events API (for webhooks, if you use them)
  post "/slack/events", to: "slack_events#create"
  
  # GitHub OAuth routes (if needed)
  get "/github/oauth", to: "github_oauth#index", as: :github_oauth
  get "/github/oauth/authorize", to: "github_oauth#authorize", as: :github_oauth_authorize
  get "/github/oauth/callback", to: "github_oauth#callback", as: :github_oauth_callback
  get "/github/oauth/success", to: "github_oauth#success", as: :github_oauth_success
end