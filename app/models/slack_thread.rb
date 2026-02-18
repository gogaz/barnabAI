# frozen_string_literal: true

class SlackThread < ApplicationRecord
  belongs_to :pull_request
  has_many :conversations, dependent: :destroy
end
