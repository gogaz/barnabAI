# frozen_string_literal: true

require "set"

class ActionExecutionService
  def initialize(user, pull_request: nil, slack_installation: nil)
    @user = user
    @pull_request = pull_request
    @slack_installation = slack_installation
    @github_service = GithubService.new(@user)
    @ai_provider = AIProviderFactory.create
  end

  def execute(intent, parameters)
    puts "=" * 80
    puts "EXECUTING ACTION: #{intent}"
    puts "Parameters: #{parameters.inspect}"
    puts "=" * 80
    case intent.to_s
    when "SUMMARIZE_EXISTING_PRS"
      execute_summarize_existing_prs(parameters)
    when "pull_request_details_summary"
      execute_pull_request_details_summary(parameters)
    when "merge_pr"
      execute_merge_pr(parameters)
    when "comment_on_pr"
      execute_comment_on_pr(parameters)
    when "get_pr_info"
      execute_get_pr_info(parameters)
    when "create_pr"
      execute_create_pr(parameters)
    when "run_specs"
      execute_run_specs(parameters)
    when "start_pull_request_workflow"
      execute_start_pull_request_workflow(parameters)
    when "list_prs_by_teams"
      execute_list_prs_by_teams(parameters)
    when "get_pr_files"
      execute_get_pr_files(parameters)
    when "approve_pr"
      execute_approve_pr(parameters)
    when "general_chat"
      { success: false, message: "This is a general chat message, no action needed." }
    else
      { success: false, message: "Unknown intent: #{intent}" }
    end
  rescue StandardError => e
    Rails.logger.error("Action execution failed: #{e.message}")
    { success: false, message: "Failed to execute action: #{e.message}" }
  end

  private

  def execute_summarize_existing_prs(parameters)
    # Get user's GitHub username
    github_username = @user.primary_github_token&.github_username
    raise ArgumentError, "User has no GitHub token connected" unless github_username

    # Extract filters from parameters (default to open if not specified)
    filters = parameters[:filters] || parameters["filters"] || { state: "open" }
    
    Rails.logger.info("🔍 Filters received: #{filters.inspect}")
    
    # Disambiguate repository name(s) if provided
    if filters[:repository] || filters["repository"]
      repo_value = filters[:repository] || filters["repository"]
      
      # Handle both single repository (string) and multiple repositories (array)
      repositories = if repo_value.is_a?(Array)
        repo_value
      else
        [repo_value]
      end
      
      disambiguated_repos = []
      errors = []
      
      repositories.each do |repo_name|
        # Only disambiguate if not already in owner/repo format
        if repo_name.include?("/")
          disambiguated_repos << repo_name
        else
          begin
            disambiguated_repo = @github_service.disambiguate_repository(repo_name)
            
            if disambiguated_repo.nil?
              errors << "Repository '#{repo_name}' not found in your accessible repositories."
            else
              disambiguated_repos << disambiguated_repo
            end
          rescue ArgumentError => e
            # Multiple matches - add to errors
            errors << e.message
          end
        end
      end
      
      # If there are errors, return them
      if errors.any?
        return {
          success: false,
          message: errors.join(" ")
        }
      end
      
      # Update filter with disambiguated repository names
      # If original was a single string, return a single string; if array, return array
      filters = filters.dup
      if repo_value.is_a?(Array)
        filters[:repository] = disambiguated_repos
        filters["repository"] = disambiguated_repos
      else
        filters[:repository] = disambiguated_repos.first
        filters["repository"] = disambiguated_repos.first
      end
    end
    
    begin
      # Get PRs for the user with applied filters
      prs = @github_service.list_user_pull_requests(github_username, filters: filters)
    rescue ArgumentError => e
      # Handle repository access errors or invalid queries
      return {
        success: false,
        message: e.message
      }
    end

    state = filters[:state] || filters["state"] || "open"
    state_label = state == "open" ? "open" : state
    
    if prs.empty?
      {
        success: true,
        message: "You don't have any #{state_label} pull requests matching your criteria at the moment.",
        data: { prs: [] }
      }
    else
      # Return PRs individually for separate messages
      # Format PRs with repository and URL information
      formatted_prs = prs.map do |pr|
        repo_full_name = pr.head.repo.full_name rescue pr.base.repo.full_name rescue "unknown/repo"
        pr_info = format_pr_info(pr)
        # Get lines changed stats (additions + deletions)
        additions = pr.additions || 0
        deletions = pr.deletions || 0
        total_changes = additions + deletions
        
        pr_info.merge(
          repository: repo_full_name,
          url: pr.html_url,
          created_at: pr.created_at,
          additions: additions,
          deletions: deletions,
          total_changes: total_changes
        )
      end
      
      {
        success: true,
        message: "Found #{prs.count} #{state_label} pull request#{'s' if prs.count > 1}",
        data: { 
          prs: formatted_prs,
          multiple_messages: true # Flag to indicate we want one message per PR
        }
      }
    end
  end

  def build_prs_summary(prs, filters = {})
    state = filters[:state] || filters["state"] || "open"
    state_label = state == "open" ? "open" : state
    
    summary = "Here's a summary of your #{prs.count} #{state_label} pull request#{'s' if prs.count > 1}:\n\n"
    
    prs.each_with_index do |pr, index|
      # Extract repository name from PR object
      repo_full_name = pr.head.repo.full_name rescue pr.base.repo.full_name rescue "unknown/repo"
      
      summary += "#{index + 1}. *PR ##{pr.number}*: #{pr.title}\n"
      summary += "   Repository: #{repo_full_name}\n"
      summary += "   State: #{pr.state}\n"
      summary += "   Created: #{pr.created_at.strftime('%Y-%m-%d')}\n"
      summary += "   Link: <#{pr.html_url}|View PR>\n"
      summary += "\n"
    end

    summary
  end

  def execute_merge_pr(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Pull request is required" unless @pull_request

    result = @github_service.merge_pull_request(
      @pull_request.repository,
      pr_number
    )

    {
      success: true,
      message: "Successfully merged PR ##{pr_number}",
      data: result
    }
  end

  def execute_comment_on_pr(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    message = parameters[:message]
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Message is required" unless message
    raise ArgumentError, "Pull request is required" unless @pull_request

    result = @github_service.create_comment(
      @pull_request.repository,
      pr_number,
      message
    )

    {
      success: true,
      message: "Comment posted on PR ##{pr_number}",
      data: result
    }
  end

  def execute_get_pr_info(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Pull request is required" unless @pull_request

    pr_data = @github_service.get_pull_request(@pull_request.repository, pr_number)
    comments = @github_service.get_comments(@pull_request.repository, pr_number)
    files = @github_service.get_files(@pull_request.repository, pr_number)

    {
      success: true,
      message: "PR ##{pr_number} information",
      data: {
        pr: format_pr_info(pr_data),
        comments_count: comments&.count || 0,
        files_count: files&.count || 0,
        files: files&.map(&:filename) || []
      }
    }
  end

  def execute_pull_request_details_summary(parameters)
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

  def execute_create_pr(parameters)
    branch_name = parameters[:branch_name]
    base_branch = parameters[:base_branch] || "main"
    title = parameters[:title]
    raise ArgumentError, "Branch name is required" unless branch_name
    raise ArgumentError, "Title is required" unless title
    raise ArgumentError, "Pull request is required" unless @pull_request

    result = @github_service.create_pull_request(
      @pull_request.repository,
      title,
      branch_name,
      base_branch
    )

    {
      success: true,
      message: "Created PR ##{result.number}: #{title}",
      data: result
    }
  end

  def execute_run_specs(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    workflow_file = parameters[:workflow_file] || ".github/workflows/specs.yml"
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Pull request is required" unless @pull_request

    # Get the head branch for the workflow
    pr_data = @github_service.get_pull_request(@pull_request.repository, pr_number)
    ref = pr_data.head.ref

    result = @github_service.trigger_workflow(
      @pull_request.repository,
      workflow_file,
      ref: ref
    )

    {
      success: true,
      message: "Triggered specs workflow for PR ##{pr_number}",
      data: result
    }
  end

  def execute_start_pull_request_workflow(parameters)
    Rails.logger.info("execute_start_pull_request_workflow - parameters: #{parameters.inspect}")
    Rails.logger.info("execute_start_pull_request_workflow - @pull_request: #{@pull_request.inspect}")
    
    pr_number = parameters[:pr_number] || parameters["pr_number"] || @pull_request&.number
    Rails.logger.info("execute_start_pull_request_workflow - pr_number after first check: #{pr_number.inspect}")
    
    # Convert to integer if it's a string representation of a number
    pr_number = pr_number.to_i if pr_number && pr_number.to_s.match?(/^\d+$/)
    Rails.logger.info("execute_start_pull_request_workflow - pr_number after conversion: #{pr_number.inspect}")
    
    unless pr_number && pr_number > 0
      Rails.logger.error("execute_start_pull_request_workflow - PR number is missing or invalid")
      raise ArgumentError, "PR number is required"
    end

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

    # Get PR data to find the head branch
    pr_data = @github_service.get_pull_request(repository, pr_number)
    raise ArgumentError, "PR ##{pr_number} not found in #{repository.full_name}" unless pr_data

    head_branch = pr_data.head.ref

    # Try to find the latest failed workflow run for this branch
    workflow_runs = @github_service.get_workflow_runs(
      repository,
      branch: head_branch,
      per_page: 10
    )

    # Find the most recent failed run
    failed_run = workflow_runs.find { |run| run[:conclusion] == "failure" }

    if failed_run
      # Re-run failed jobs from the failed run
      @github_service.rerun_failed_workflow(repository, failed_run[:id])
      {
        success: true,
        message: "Re-running failed jobs from workflow run ##{failed_run[:id]} for PR ##{pr_number}",
        data: { run_id: failed_run[:id], workflow_name: failed_run[:name] }
      }
    else
      # No failed run found, trigger the workflow again on the branch
      # Try to find the workflow file (default to common CI workflow)
      workflow_file = parameters[:workflow_file] || ".github/workflows/ci.yml"
      
      @github_service.trigger_workflow(
        repository,
        workflow_file,
        ref: head_branch
      )
      
      {
        success: true,
        message: "Triggered workflow for PR ##{pr_number} on branch #{head_branch}",
        data: { branch: head_branch, workflow_file: workflow_file }
      }
    end
  rescue ArgumentError => e
    {
      success: false,
      message: e.message
    }
  rescue StandardError => e
    Rails.logger.error("Failed to start pull request workflow: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    {
      success: false,
      message: "Failed to start workflow: #{e.message}"
    }
  end

  def execute_get_pr_files(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Pull request is required" unless @pull_request

    files = @github_service.get_files(@pull_request.repository, pr_number)

    {
      success: true,
      message: "Files changed in PR ##{pr_number}",
      data: {
        files: files.map do |file|
          {
            filename: file.filename,
            status: file.status,
            additions: file.additions,
            deletions: file.deletions,
            changes: file.changes
          }
        end
      }
    }
  end

  def execute_approve_pr(parameters)
    pr_number = parameters[:pr_number] || @pull_request&.number
    body = parameters[:message] || "Approved via Slack bot"
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Pull request is required" unless @pull_request

    result = @github_service.approve_pull_request(
      @pull_request.repository,
      pr_number,
      body: body
    )

    {
      success: true,
      message: "Approved PR ##{pr_number}",
      data: result
    }
  end

  def disambiguate_repository_for_user(repo_name)
    # If already in full format (owner/repo), return as is
    return repo_name if repo_name.include?("/")
    
    # Use GithubService to disambiguate
    @github_service.disambiguate_repository(repo_name)
  rescue ArgumentError => e
    # Multiple matches - re-raise with clearer message
    raise ArgumentError, e.message
  end

  def find_or_create_repository(repo_full_name)
    raise ArgumentError, "Slack installation is required to find/create repository" unless @slack_installation
    
    # Parse repository full_name (owner/repo-name)
    parts = repo_full_name.split("/")
    raise ArgumentError, "Invalid repository format. Expected 'owner/repo-name'" unless parts.length == 2
    
    owner = parts[0]
    name = parts[1]
    
    # Find or create repository
    Repository.find_or_create_by!(
      slack_installation: @slack_installation,
      full_name: repo_full_name
    ) do |repo|
      repo.owner = owner
      repo.name = name
    end
  end

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

  def execute_list_prs_by_teams(parameters)
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

  # Determine impacted teams from CODEOWNERS file
  def determine_impacted_teams(repository, files)
    matcher = CodeownersMatcher.new(@github_service, repository)
    matcher.determine_impacted_teams(files)
  end
end
