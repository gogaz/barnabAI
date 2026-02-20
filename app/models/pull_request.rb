# frozen_string_literal: true

class PullRequest < ApplicationRecord
  validates :number, presence: true, uniqueness: { scope: :repository_id }
end
