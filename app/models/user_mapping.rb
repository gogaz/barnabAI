# frozen_string_literal: true

class UserMapping < ApplicationRecord
  validates :slack_user_id, presence: true
  validates :github_username, presence: true
end
