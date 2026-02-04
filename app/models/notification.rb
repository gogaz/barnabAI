# frozen_string_literal: true

# Note: The notifications table was dropped in migration 20260117000004
# This model is kept for reference in case notifications are re-implemented
class Notification < ApplicationRecord
  belongs_to :pull_request

  validates :notification_type, presence: true

  scope :processed, -> { where(processed: true) }
  scope :unprocessed, -> { where(processed: [false, nil]) }
end
