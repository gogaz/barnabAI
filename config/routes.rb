Rails.application.routes.draw do
  root to: 'home#index'

  get "/github/oauth", to: "github_oauth#index", as: :github_oauth
  get "/github/oauth/authorize", to: "github_oauth#authorize", as: :github_oauth_authorize
  get "/github/oauth/callback", to: "github_oauth#callback", as: :github_oauth_callback
  get "/github/oauth/success", to: "github_oauth#success", as: :github_oauth_success

  post "/github/webhooks", to: "github_webhooks#create", as: :github_webhooks
end
