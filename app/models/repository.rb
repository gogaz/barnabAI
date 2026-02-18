# frozen_string_literal: true

class Repository < ApplicationRecord
  has_many :pull_requests, dependent: :destroy
  has_many :slack_threads, through: :pull_requests

  validates :full_name, presence: true, uniqueness: true
  validates :name, presence: true
  validates :owner, presence: true
end
