# frozen_string_literal: true

class GithubToken < ApplicationRecord
  belongs_to :user, inverse_of: :github_tokens

  # Encrypt sensitive tokens using ActiveRecord::Encryption
  encrypts :token_encrypted

  def token
    token_encrypted
  end

  def token=(value)
    self.token_encrypted = value
  end
end
