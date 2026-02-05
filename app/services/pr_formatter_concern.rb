# frozen_string_literal: true

module PrFormatterConcern
  extend ActiveSupport::Concern

  private

  def format_pr_info(pr_data)
    {
      number: pr_data.number,
      title: pr_data.title,
      state: pr_data.state,
      author: pr_data.user.login,
      head_branch: pr_data.head.ref,
      base_branch: pr_data.base.ref,
      created_at: pr_data.created_at,
      updated_at: pr_data.updated_at,
      merged_at: pr_data.merged_at,
      body: pr_data.body
    }
  end
end
