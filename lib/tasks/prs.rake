# frozen_string_literal: true

namespace :prs do
  desc "Import PRs since a given timestamp and update their impacted teams"
  task :import_since, [:since] => :environment do |_t, args|
    # Parse the since parameter
    since_time = if args[:since]
      begin
        Time.parse(args[:since])
      rescue ArgumentError
        puts "❌ Invalid timestamp format: #{args[:since]}"
        puts "Please use a format like: '2024-01-01' or '2024-01-01 12:00:00' or '7 days ago'"
        exit 1
      end
    else
      # Default to 7 days ago
      7.days.ago
    end

    puts "📅 Fetching PRs updated since: #{since_time}"
    puts "=" * 80

    total_prs = 0
    total_jobs = 0
    errors = []

    # Iterate through all repositories
    Repository.find_each do |repository|
      puts "\n📦 Processing repository: #{repository.full_name}"

      # Get a user for GitHub API access
      user = User.first
      unless user
        puts "  ⚠️  No users found, skipping"
        errors << { repository: repository.full_name, error: "No users found" }
        next
      end

      github_service = Github::Client.new(user)

      begin
        # Fetch PRs updated since the given timestamp
        filtered_prs = github_service.list_pull_requests_since(
          repository,
          since: since_time,
          state: "all", # Get all PRs (open, closed, merged)
          limit: 100
        )

        if filtered_prs.empty?
          puts "  ✓ No PRs updated since #{since_time}"
          next
        end

        puts "  ✓ Found #{filtered_prs.count} PR(s) to process"

        # Enqueue job for each PR
        filtered_prs.each do |pr|
          begin
            UpdatePullRequestTeamsJob.perform_later(repository.id, pr.number)
            total_jobs += 1
            puts "    → Enqueued job for PR ##{pr.number}: #{pr.title}"
          rescue StandardError => e
            error_msg = "Failed to enqueue job for PR ##{pr.number}: #{e.message}"
            puts "    ❌ #{error_msg}"
            errors << { repository: repository.full_name, pr: pr.number, error: error_msg }
          end
        end

        total_prs += filtered_prs.count
      rescue Octokit::NotFound
        puts "  ⚠️  Repository not found or no access"
        errors << { repository: repository.full_name, error: "Repository not found or no access" }
      rescue Octokit::Unauthorized
        puts "  ⚠️  Unauthorized access to repository"
        errors << { repository: repository.full_name, error: "Unauthorized access" }
      rescue StandardError => e
        error_msg = "Error processing repository: #{e.message}"
        puts "  ❌ #{error_msg}"
        errors << { repository: repository.full_name, error: error_msg }
      end
    end

    # Summary
    puts "\n" + "=" * 80
    puts "📊 Summary:"
    puts "  • Total PRs found: #{total_prs}"
    puts "  • Total jobs enqueued: #{total_jobs}"
    puts "  • Errors: #{errors.count}"

    if errors.any?
      puts "\n⚠️  Errors encountered:"
      errors.each do |error|
        puts "  • #{error[:repository]}"
        puts "    PR: ##{error[:pr]}" if error[:pr]
        puts "    Error: #{error[:error]}"
      end
    end

    puts "\n✅ Import task completed!"
  end

  desc "Import all open PRs and update their impacted teams"
  task import_open: :environment do
    puts "📅 Fetching all open PRs"
    puts "=" * 80

    total_prs = 0
    total_jobs = 0
    errors = []

    # Iterate through all repositories
    Repository.find_each do |repository|
      puts "\n📦 Processing repository: #{repository.full_name}"

      # Get a user for GitHub API access
      user = User.first
      unless user
        puts "  ⚠️  No users found, skipping"
        errors << { repository: repository.full_name, error: "No users found" }
        next
      end

      github_service = Github::Client.new(user)

      begin
        # Fetch all open PRs
        prs = github_service.list_pull_requests(repository, state: "open", limit: 100)

        if prs.empty?
          puts "  ✓ No open PRs found"
          next
        end

        puts "  ✓ Found #{prs.count} open PR(s) to process"

        # Enqueue job for each PR
        prs.each do |pr|
          begin
            UpdatePullRequestTeamsJob.perform_later(repository.id, pr.number)
            total_jobs += 1
            puts "    → Enqueued job for PR ##{pr.number}: #{pr.title}"
          rescue StandardError => e
            error_msg = "Failed to enqueue job for PR ##{pr.number}: #{e.message}"
            puts "    ❌ #{error_msg}"
            errors << { repository: repository.full_name, pr: pr.number, error: error_msg }
          end
        end

        total_prs += prs.count
      rescue Octokit::NotFound
        puts "  ⚠️  Repository not found or no access"
        errors << { repository: repository.full_name, error: "Repository not found or no access" }
      rescue Octokit::Unauthorized
        puts "  ⚠️  Unauthorized access to repository"
        errors << { repository: repository.full_name, error: "Unauthorized access" }
      rescue StandardError => e
        error_msg = "Error processing repository: #{e.message}"
        puts "  ❌ #{error_msg}"
        errors << { repository: repository.full_name, error: error_msg }
      end
    end

    # Summary
    puts "\n" + "=" * 80
    puts "📊 Summary:"
    puts "  • Total PRs found: #{total_prs}"
    puts "  • Total jobs enqueued: #{total_jobs}"
    puts "  • Errors: #{errors.count}"

    if errors.any?
      puts "\n⚠️  Errors encountered:"
      errors.each do |error|
        puts "  • #{error[:repository]}"
        puts "    PR: ##{error[:pr]}" if error[:pr]
        puts "    Error: #{error[:error]}"
      end
    end

    puts "\n✅ Import task completed!"
  end
end
