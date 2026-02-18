# frozen_string_literal: true

namespace :slack do
  desc "Start Slack Socket Mode connection"
  task connect: :environment do
    puts "Starting Slack Socket Mode connection..."
    
    begin
      app_token = ENV.fetch("SLACK_APP_TOKEN") do
        raise "SLACK_APP_TOKEN environment variable is required for Socket Mode"
      end

      # EventMachine.run blocks and keeps the process alive
      Slack::SocketConnector.start(app_token: app_token)
      
      # This line should not be reached because EventMachine.run blocks
      # But if it is, something went wrong
      puts "❌ Failed to start Slack Socket Mode connection"
      exit 1
    rescue Interrupt
      puts "\n🛑 Stopping Slack Socket Mode connection..."
      exit 0
    rescue StandardError => e
      puts "❌ Error: #{e.message}"
      puts e.backtrace.join("\n")
      exit 1
    end
  end

  desc "Test Slack auth and display bot info (bot_user_id, bot_id)"
  task test_auth: :environment do
    require "net/http"
    require "json"

    bot_token = ENV.fetch("SLACK_BOT_TOKEN") do
      raise "SLACK_BOT_TOKEN environment variable is required"
    end

    uri = URI("https://slack.com/api/auth.test")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{bot_token}"

    response = http.request(request)
    data = JSON.parse(response.body)

    if data["ok"]
      puts "✅ Slack auth successful!"
      puts ""
      puts "SLACK_BOT_USER_ID=#{data['user_id']}"
      puts "SLACK_BOT_ID=#{data['bot_id']}"
      puts ""
      puts "Additional info:"
      puts "  Team: #{data['team']}"
      puts "  Bot: #{data['user']}"
      puts "  URL: #{data['url']}"
    else
      puts "❌ Slack auth failed: #{data['error']}"
      exit 1
    end
  end
end
