# frozen_string_literal: true

class UserMapping < ApplicationRecord
  belongs_to :slack_installation

  validates :slack_user_id, presence: true
  validates :github_username, presence: true
  validates :github_username, uniqueness: {
    scope: [:slack_installation_id, :slack_user_id],
    message: "Mapping already exists for this user"
  }
end
