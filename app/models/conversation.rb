# frozen_string_literal: true

class Conversation < ApplicationRecord
  belongs_to :user
  belongs_to :slack_thread, optional: true

  # messages is a JSONB array storing conversation history
  # Format: [{ role: "user"|"assistant", content: "...", timestamp: "..." }]
end
