# frozen_string_literal: true

class User < ApplicationRecord
  has_many :github_tokens, dependent: :destroy

  # Primary GitHub token (first one created)
  has_one :primary_github_token, -> { order(created_at: :asc) }, class_name: "GithubToken", inverse_of: :user

  validates :slack_user_id, presence: true, uniqueness: true

  # Helper method to check for GitHub token
  def has_github_token?
    primary_github_token.present?
  end
end
