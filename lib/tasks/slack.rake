# frozen_string_literal: true

namespace :slack do
  desc "Start Slack Socket Mode connection"
  task connect: :environment do
    puts "Starting Slack Socket Mode connection..."
    
    begin
      SlackService.start_socket_mode
      
      if SlackService.socket_mode_running?
        puts "✅ Slack Socket Mode connection started successfully"
        puts "Press Ctrl+C to stop"
        
        # Keep the process alive
        loop do
          sleep 1
        end
      else
        puts "❌ Failed to start Slack Socket Mode connection"
        exit 1
      end
    rescue Interrupt
      puts "\n🛑 Stopping Slack Socket Mode connection..."
      exit 0
    rescue StandardError => e
      puts "❌ Error: #{e.message}"
      puts e.backtrace.join("\n")
      exit 1
    end
  end
end
