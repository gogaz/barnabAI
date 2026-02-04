# frozen_string_literal: true

class Repository < ApplicationRecord
  belongs_to :slack_installation
  has_many :pull_requests, dependent: :destroy
  has_many :slack_threads, through: :pull_requests

  validates :full_name, presence: true, uniqueness: { scope: :slack_installation_id }
  validates :name, presence: true
  validates :owner, presence: true
end
