# frozen_string_literal: true

class SlackInstallation < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :repositories, dependent: :destroy
  has_many :slack_threads, dependent: :destroy
  has_many :user_mappings, dependent: :destroy

  validates :team_id, presence: true, uniqueness: true

  # Encrypt sensitive tokens using ActiveRecord::Encryption
  encrypts :bot_token_encrypted
  encrypts :access_token_encrypted

  def bot_token
    bot_token_encrypted
  end

  def bot_token=(value)
    self.bot_token_encrypted = value
  end

  def access_token
    access_token_encrypted
  end

  def access_token=(value)
    self.access_token_encrypted = value
  end
end
