# frozen_string_literal: true

class MaintainSlackConnectionsJob < ApplicationJob
  queue_as :default

  def perform
    # This job maintains Socket Mode connection
    # Socket Mode uses one global connection for all workspaces
    # This job should be run periodically (e.g., every 5 minutes) to ensure connection stays alive

    begin
      # Check if connection is alive and restart if needed
      # In production, you might want to track connection state more carefully
      SlackService.start_socket_mode
    rescue StandardError => e
      Rails.logger.error("Failed to maintain Slack Socket Mode connection: #{e.message}")
    end
  end
end

