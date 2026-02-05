# frozen_string_literal: true

class Actions::ListPrsByTeamsAction < Actions::BaseAction
  def execute(parameters)
    teams = parameters[:teams] || parameters["teams"]
    raise ArgumentError, "Teams are required" unless teams&.any?

    # Normalize teams to array
    teams_array = teams.is_a?(Array) ? teams : [teams]
    # Ensure teams start with @ if they don't already
    teams_array = teams_array.map { |team| team.start_with?("@") ? team : "@#{team}" }

    # Get duration (default to 7 days)
    days = parameters[:days] || parameters["days"] || 7
    days = days.to_i if days.respond_to?(:to_i)
    days = 7 if days <= 0 # Ensure positive number
    
    # Calculate the cutoff date
    cutoff_date = days.days.ago

    # Get repositories for the slack installation
    repositories = @slack_installation&.repositories || []
    raise ArgumentError, "No repositories found for this installation" if repositories.empty?

    # Find PRs that have any of the specified teams in their impacted_teams
    # Exclude PRs that contain " MEP " (case sensitive) in the title
    # Filter by github_created_at >= cutoff_date
    # Use @> (contains) operator: check if impacted_teams contains any of the teams
    # For each team, check if impacted_teams contains that team using @>
    team_conditions = teams_array.map { "impacted_teams::text[] @> ARRAY[?]::text[]" }
    matching_prs = PullRequest.joins(:repository)
      .where(repositories: { slack_installation_id: @slack_installation.id })
      .where("(#{team_conditions.join(' OR ')})", *teams_array)
      .where.not("title LIKE ?", "%MEP%")
      .where("github_created_at >= ?", cutoff_date)
      .includes(:repository)
      .order(github_created_at: :desc)
      .limit(50)

    if matching_prs.empty?
      {
        success: true,
        message: "No PRs found impacting teams: #{teams_array.join(', ')}",
        data: { prs: [] }
      }
    else
      # Fetch file diffs for each PR
      pr_list_with_diffs = matching_prs.map do |pr|
        begin
          files = @github_service.get_files(pr.repository, pr.number)
          # Extract patch/diff information from files
          file_changes = files.map do |file|
            {
              filename: file.filename,
              status: file.status,
              additions: file.additions,
              deletions: file.deletions,
              changes: file.changes,
              patch: file.patch # This contains the actual diff
            }
          end

          {
            number: pr.number,
            title: pr.title,
            state: pr.state,
            repository: pr.repository.full_name,
            url: "https://github.com/#{pr.repository.full_name}/pull/#{pr.number}",
            impacted_teams: pr.impacted_teams,
            created_at: pr.github_created_at&.strftime("%Y-%m-%d"),
            files: file_changes
          }
        rescue StandardError => e
          Rails.logger.warn("Failed to fetch files for PR ##{pr.number}: #{e.message}")
          # Include PR without file diffs if fetch fails
          {
            number: pr.number,
            title: pr.title,
            state: pr.state,
            repository: pr.repository.full_name,
            url: "https://github.com/#{pr.repository.full_name}/pull/#{pr.number}",
            impacted_teams: pr.impacted_teams,
            created_at: pr.github_created_at&.strftime("%Y-%m-%d"),
            files: []
          }
        end
      end

      # Generate AI summary with grouping and diff analysis
      blocks = build_prs_summary_blocks(pr_list_with_diffs, teams_array, days)

      {
        success: true,
        message: "Found #{matching_prs.count} PR(s) impacting teams: #{teams_array.join(', ')}",
        data: { prs: pr_list_with_diffs, teams: teams_array, blocks: blocks }
      }
    end
  rescue ArgumentError => e
    {
      success: false,
      message: e.message
    }
  rescue StandardError => e
    Rails.logger.error("Failed to list PRs by teams: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    {
      success: false,
      message: "Failed to list PRs: #{e.message}"
    }
  end

  private

  def build_prs_summary_blocks(pr_list, teams_array, days)
    # Build prompt for AI to summarize and group PRs based on file diffs
    system_message = "You are a helpful assistant that summarizes and groups GitHub pull requests by analyzing their file changes. " \
                     "You MUST return ONLY valid JSON in Slack Block Kit format. " \
                     "Do NOT wrap your response in markdown code blocks. " \
                     "Do NOT add any explanation or text before or after the JSON. " \
                     "Return ONLY the raw JSON array of Slack blocks. " \
                     "Analyze the file diffs (patches) for each PR to understand what changes were made. " \
                     "Group related PRs together based on the changes they make (e.g., PRs working on the same feature, same area, or related changes). " \
                     "For each PR, ALWAYS include: " \
                     "- A link to the PR (using Slack's link format: <url|text>) " \
                     "- A concise summary explaining what happened in this PR based on the file diffs (2-3 sentences max) " \
                     "- The PR number and repository " \
                     "- Key files or areas that were changed " \
                     "Use Slack Block Kit sections to group related PRs. " \
                     "Start with a header summarizing the total number of PRs found and a brief overview of what changed across all PRs. " \
                     "Then group PRs by theme/area/feature, with clear section headers. " \
                     "Keep descriptions concise, actionable, and focused on what actually changed in the code."

    # Prepare PR data with file diffs for AI analysis
    # Limit patch size to avoid token limits (keep first 500 lines of each patch)
    prs_data = pr_list.map do |pr|
      diffs = (pr[:files] || []).map do |f|
        patch = f[:patch]
        # Truncate very long patches to avoid token limits
        if patch && patch.length > 5000
          patch_lines = patch.split("\n")
          truncated_patch = patch_lines.first(500).join("\n") + "\n... (truncated)"
          { filename: f[:filename], patch: truncated_patch }
        elsif patch
          { filename: f[:filename], patch: patch }
        else
          nil
        end
      end.compact

      {
        number: pr[:number],
        title: pr[:title],
        state: pr[:state],
        repository: pr[:repository],
        url: pr[:url],
        created_at: pr[:created_at],
        files_changed: (pr[:files] || []).map { |f| f[:filename] },
        file_changes_summary: (pr[:files] || []).map { |f| "#{f[:filename]}: #{f[:status]} (+#{f[:additions]}/-#{f[:deletions]})" },
        diffs: diffs
      }
    end

    user_message = <<~PROMPT
      Please analyze these pull requests and their file changes, then summarize and group them as Slack Block Kit JSON blocks:

      Teams: #{teams_array.join(', ')}
      Time period: Last #{days} days
      Total PRs: #{pr_list.count}

      PRs with their file changes and diffs:
      #{prs_data.to_json}

      For each PR, analyze the file diffs (patches) to understand what changes were made. Then:
      1. Provide a brief overview (2-3 sentences) summarizing what happened across all PRs
      2. Group related PRs together based on the changes they make
      3. For each PR, include:
         - Link to the PR (format: <https://github.com/owner/repo/pull/123|#123: Title>)
         - A concise explanation of what happened in this PR based on the diffs (2-3 sentences)
         - State (open/closed/merged)
         - Key files or areas that were changed

      Focus on explaining what actually changed in the code based on the diffs, not just the PR title.

      Return ONLY a valid JSON array of Slack Block Kit blocks. No markdown, no code blocks, just raw JSON.
    PROMPT

    messages = [
      { role: "system", content: system_message },
      { role: "user", content: user_message }
    ]

    response = @ai_provider.chat_completion(
      messages,
      max_tokens: 4000, # Increased for diff analysis and multiple PRs
      response_format: :json
    )

    # Parse the JSON response (should be an array of Slack blocks)
    blocks = JSON.parse(response)
    blocks.is_a?(Array) ? blocks : [blocks]
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse AI response as JSON: #{e.message}")
    Rails.logger.error("Response was: #{response}")
    # Fallback to simple text format
    pr_text = pr_list.map { |pr| "• <#{pr[:url]}|##{pr[:number]}: #{pr[:title]}> (#{pr[:state]})" }.join("\n")
    [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "Found #{pr_list.count} PR(s) impacting teams: #{teams_array.join(', ')}\n\n#{pr_text}"
        }
      }
    ]
  rescue StandardError => e
    Rails.logger.error("Failed to build PRs summary blocks: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    # Fallback to simple text format
    pr_text = pr_list.map { |pr| "• <#{pr[:url]}|##{pr[:number]}: #{pr[:title]}> (#{pr[:state]})" }.join("\n")
    [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "Found #{pr_list.count} PR(s) impacting teams: #{teams_array.join(', ')}\n\n#{pr_text}"
        }
      }
    ]
  end
end
