# frozen_string_literal: true

class SlackThread < ApplicationRecord
  belongs_to :pull_request
  belongs_to :slack_installation
  has_many :conversations, dependent: :destroy
end
