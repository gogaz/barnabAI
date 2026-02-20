# frozen_string_literal: true

class PullRequest < ApplicationRecord
  validates :number, presence: true, uniqueness: { scope: :repository_full_name }
  validates :repository_full_name, presence: true
end
