# frozen_string_literal: true

module AiProviderAccessConcern
  extend ActiveSupport::Concern

  private

  def ai_provider
    @ai_provider ||= AIProviderFactory.create
  end
end
