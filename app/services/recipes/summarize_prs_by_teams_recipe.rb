# frozen_string_literal: true

class Recipes::SummarizePrsByTeamsRecipe < Recipes::BaseRecipe
  function_code "recipe_summarize_prs_by_teams"
  function_description "Summarize merged pull requests impacting specific teams, grouped by theme with AI analysis of file diffs. " \
                       "Only merged PRs are tracked — open or closed (unmerged) PRs will not appear. " \
                       "Teams are derived from CODEOWNERS; pass team handles like '@org/team-name'. " \
                       "Results are directly sent to the user without further processing."
  function_parameters({
    type: "object",
    properties: {
      teams: {
        type: "array",
        items: { type: "string" },
        description: "Team handles to filter by (e.g., ['@organization/core-team', '@rails/founders']). Be flexible with typos and partial matches."
      },
      days: {
        type: "integer",
        description: "Number of days to look back. Examples: 'last 3 days' -> 3, 'past week' -> 7, 'last month' -> 30. Defaults to 7 if not specified."
      }
    },
    required: ["teams"]
  })

  def execute(parameters)
    teams = parameters[:teams] || parameters["teams"]
    raise ArgumentError, "Teams are required" unless teams&.any?

    teams_array = teams.is_a?(Array) ? teams : [teams]
    teams_array = teams_array.map { |team| team.start_with?("@") ? team : "@#{team}" }

    days = (parameters[:days] || parameters["days"] || 7).to_i
    days = 7 if days <= 0
    cutoff_date = days.days.ago

    team_conditions = teams_array.map { "impacted_teams::text[] @> ARRAY[?]::text[]" }
    matching_prs = PullRequest
      .where("(#{team_conditions.join(' OR ')})", *teams_array)
      .where("github_created_at >= ?", cutoff_date)
      .order(github_created_at: :desc)
      .limit(50)

    if matching_prs.empty?
      Slack::MessageBuilder.new
        .add_context_block("No merged PRs found impacting teams #{teams_array.join(', ')} in the last #{days} days.")
        .send!(channel: channel_id, thread_ts: context.thread_ts)
      return
    end

    pr_list_with_diffs = matching_prs.map do |pr|
      files = github_client.get_files(pr.repository_full_name, pr.number)
      file_changes = (files || []).map do |file|
        {
          filename: file.filename,
          status: file.status,
          additions: file.additions,
          deletions: file.deletions,
          changes: file.changes,
          patch: file.patch
        }
      end

      {
        number: pr.number,
        title: pr.title,
        state: pr.state,
        author: pr.author,
        repository: pr.repository_full_name,
        url: "https://github.com/#{pr.repository_full_name}/pull/#{pr.number}",
        impacted_teams: pr.impacted_teams,
        created_at: pr.github_created_at&.strftime("%Y-%m-%d"),
        files: file_changes
      }
    end

    blocks_json = build_ai_summary(pr_list_with_diffs, teams_array, days)

    Slack::Client.send_message(
      channel: channel_id,
      thread_ts: context.thread_ts,
      blocks: blocks_json,
      text: "Summary of #{matching_prs.count} merged PRs for #{teams_array.join(', ')}"
    )

    nil
  end

  private

  def build_ai_summary(pr_list, teams_array, days)
    system_message = <<~SYSTEM.strip
      You are a helpful assistant that summarizes and groups GitHub pull requests by analyzing their file changes.
      You MUST return ONLY valid JSON in Slack Block Kit format.
      Do NOT wrap your response in markdown code blocks.
      Do NOT add any explanation or text before or after the JSON.
      Return ONLY the raw JSON array of Slack blocks.
      Analyze the file diffs (patches) for each PR to understand what changes were made.
      Group related PRs together based on the changes they make (e.g., PRs working on the same feature, same area, or related changes).
      For each PR, ALWAYS include:
      - A link to the PR (using Slack's link format: <url|text>)
      - A concise summary explaining what happened in this PR based on the file diffs (2-3 sentences max)
      - The PR number and repository
      - Key files or areas that were changed
      Use Slack Block Kit sections to group related PRs.
      Start with a header summarizing the total number of PRs found and a brief overview of what changed across all PRs.
      Then group PRs by theme/area/feature, with clear section headers.
      Keep descriptions concise, actionable, and focused on what actually changed in the code.
    SYSTEM

    prs_data = pr_list.map do |pr|
      diffs = (pr[:files] || []).filter_map do |f|
        next unless f[:patch]

        patch = if f[:patch].length > 5000
                  f[:patch].split("\n").first(500).join("\n") + "\n... (truncated)"
        else
                  f[:patch]
        end
        { filename: f[:filename], patch: patch }
      end

      {
        number: pr[:number],
        title: pr[:title],
        state: pr[:state],
        author: pr[:author],
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
         - merged date
         - Key files or areas that were changed

      Focus on explaining what actually changed in the code based on the diffs, not just the PR title.

      Return ONLY a valid JSON array of Slack Block Kit blocks. No markdown, no code blocks, just raw JSON.
    PROMPT

    ai_provider.chat_completion(
      [
        { role: "system", content: system_message },
        { role: "user", content: user_message }
      ],
      max_tokens: 4000,
      response_format: :json
    )
  end
end
