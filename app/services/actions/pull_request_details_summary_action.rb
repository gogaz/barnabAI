# frozen_string_literal: true

class Actions::PullRequestDetailsSummaryAction < Actions::BaseAction
  include RepositoryResolverConcern
  include PrFormatterConcern

  def execute(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    raise ArgumentError, "PR number is required" unless pr_number

    # Get repository - either from @pull_request or find/create from parameters/context
    repository = if @pull_request
      @pull_request.repository
    elsif parameters[:repository]
      repo_name = parameters[:repository]
      # Disambiguate repository name if needed (handles both "owner/repo" and "repo-name" formats)
      disambiguated_repo = disambiguate_repository_for_user(repo_name)
      raise ArgumentError, "Repository '#{repo_name}' not found in your accessible repositories." unless disambiguated_repo
      find_or_create_repository(disambiguated_repo)
    else
      raise ArgumentError, "Repository information is required. Please specify the repository (e.g., 'owner/repo-name') or use this command in a PR thread."
    end

    # Fetch all PR data
    pr_data = @github_service.get_pull_request(repository, pr_number)
    raise ArgumentError, "PR ##{pr_number} not found in #{repository.full_name}" unless pr_data

    comments = @github_service.get_comments(repository, pr_number)
    reviews = @github_service.get_reviews(repository, pr_number)
    check_runs = @github_service.get_check_runs(repository, pr_number)
    files = @github_service.get_files(repository, pr_number)

    # Build summary
    summary = build_pr_details_summary(pr_data, comments, reviews, check_runs, repository, files)

    {
      success: true,
      message: summary,
      data: {
        pr: format_pr_info(pr_data),
        comments_count: comments&.count || 0,
        reviews_count: reviews&.count || 0,
        check_runs: check_runs
      }
    }
  rescue ArgumentError => e
    {
      success: false,
      message: e.message
    }
  rescue StandardError => e
    Rails.logger.error("Failed to get PR details summary: #{e.message}")
    {
      success: false,
      message: "Failed to get PR details: #{e.message}"
    }
  end

  private

  def build_pr_details_summary(pr_data, comments, reviews, check_runs, repository, files)
    # Prepare data for AI to analyze
    pr_info = {
      number: pr_data.number,
      title: pr_data.title,
      body: pr_data.body,
      state: pr_data.state,
      repository: pr_data.head.repo.full_name,
      author: pr_data.user.login,
      created_at: pr_data.created_at,
      updated_at: pr_data.updated_at,
      merged_at: pr_data.merged_at,
      head_branch: pr_data.head.ref,
      base_branch: pr_data.base.ref,
      additions: pr_data.additions,
      deletions: pr_data.deletions,
      changed_files: pr_data.changed_files,
      html_url: pr_data.html_url
    }

    reviews_data = if reviews&.any?
      reviews.map do |review|
        {
          state: review.state,
          author: review.user.login,
          body: review.body,
          submitted_at: review.submitted_at
        }
      end
    else
      []
    end

    comments_data = if comments&.any?
      comments.map do |comment|
        {
          author: comment.user.login,
          body: comment.body,
          created_at: comment.created_at
        }
      end
    else
      []
    end

    check_runs_data = if check_runs && check_runs[:statuses]&.any?
      {
        overall_state: check_runs[:state],
        statuses: check_runs[:statuses].map do |status|
          {
            state: status[:state],
            context: status[:context],
            description: status[:description],
            target_url: status[:target_url]
          }
        end
      }
    else
      { overall_state: nil, statuses: [] }
    end

    # Fetch CODEOWNERS and determine impacted teams
    impacted_teams = determine_impacted_teams(repository, files)

    # Build prompt for AI
    system_message = "You are a helpful assistant that summarizes GitHub pull request information. " \
                     "Extract the most relevant and concise information from the provided PR data, " \
                     "including reviews, comments, workflow status, and impacted teams. " \
                     "You MUST return ONLY valid JSON in Slack Block Kit format. " \
                     "Do NOT wrap your response in markdown code blocks. " \
                     "Do NOT add any explanation or text before or after the JSON. " \
                     "Return ONLY the raw JSON array of Slack blocks. " \
                     "make sure to ALWAYS include the PR number and repository in the summary, as a link pointing to the right pull request. " \
                     "The developer already has the context of the PR, so focus on providing insights and next steps based on the current state of the PR, reviews, comments, and workflow results. " \
                     "If impacted teams are provided, include a section listing which teams are impacted by this PR based on CODEOWNERS. " \
                     "If the PR has failed checks, include a section summarizing which checks have failed and what the errors were. " \
                      "If there are reviews requesting changes, summarize the requested changes. " \
                      "If there are comments, summarize the main points of discussion. " \
                      "The goal is to provide a clear and actionable summary that helps the developer understand the current status of the PR and what they need to do next to move it forward."

    user_message = <<~PROMPT
      Please provide a concise summary of this pull request as Slack Block Kit JSON blocks:

      PR Information:
      #{pr_info.to_json}

      Reviews:
      #{reviews_data.to_json}

      Comments:
      #{comments_data.to_json}

      Workflow/Check Runs:
      #{check_runs_data.to_json}

      Impacted Teams (from CODEOWNERS):
      #{impacted_teams.to_json}

      Extract the most relevant information and return ONLY a valid JSON array of Slack Block Kit blocks. No markdown, no code blocks, just raw JSON.
    PROMPT

    messages = [
      { role: "system", content: system_message },
      { role: "user", content: user_message }
    ]

    @ai_provider.chat_completion(messages, temperature: 0.3, max_tokens: 2000, response_format: :json)
  rescue StandardError => e
    Rails.logger.error("Failed to generate PR summary with AI: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    # Fallback to basic summary if AI fails
    "*PR ##{pr_data.number}: #{pr_data.title}*\n" \
    "Repository: #{pr_data.head.repo.full_name}\n" \
    "State: #{pr_data.state}\n" \
    "Reviews: #{reviews&.count || 0}\n" \
    "Comments: #{comments&.count || 0}"
  end

  # Determine impacted teams from CODEOWNERS file
  def determine_impacted_teams(repository, files)
    matcher = CodeownersMatcher.new(@github_service, repository)
    matcher.determine_impacted_teams(files)
  end
end
