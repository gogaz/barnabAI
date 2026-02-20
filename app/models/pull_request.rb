# frozen_string_literal: true

class PullRequest < ApplicationRecord
  has_many :slack_threads, dependent: :destroy
  has_many :conversations, through: :slack_threads

  validates :number, presence: true, uniqueness: { scope: :repository_id }
end
