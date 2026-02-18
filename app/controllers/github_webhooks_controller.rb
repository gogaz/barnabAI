# frozen_string_literal: true

class GithubWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :handle_parse_error

  def create
    event_type = request.headers["X-GitHub-Event"]
    delivery_id = request.headers["X-GitHub-Delivery"]
    payload = request.request_parameters.presence || JSON.parse(request.body.read)

    Rails.logger.info("Received GitHub webhook: event=#{event_type}, delivery=#{delivery_id}")

    ProcessGithubWebhookJob.perform_later(
      event_type: event_type,
      delivery_id: delivery_id,
      payload: payload
    )

    head :ok
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse GitHub webhook payload: #{e.message}")
    head :bad_request
  end

  private

  def handle_parse_error(exception)
    Rails.logger.error("Failed to parse GitHub webhook payload: #{exception.message}")
    Rails.logger.error(request.body)

    head :bad_request
  end
end


