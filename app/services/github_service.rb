# frozen_string_literal: true

require "octokit"
require "base64"

class GithubService
  def initialize(user)
    @user = user
  end

  # Get a specific PR
  def get_pull_request(repository, pr_number)
    client.pull_request(repository.full_name, pr_number)
  rescue Octokit::NotFound
    nil
  end

  # List PRs for a repository
  def list_pull_requests(repository, state: "open", limit: 10)
    client.pull_requests(repository.full_name, state: state, per_page: limit)
  end

  # List PRs for a repository with since parameter (filters by updated_at)
  def list_pull_requests_since(repository, since:, state: "all", limit: 100)
    # Fetch PRs and filter by updated_at >= since
    # Note: GitHub API doesn't support direct since filtering for PRs endpoint,
    # so we fetch and filter client-side
    prs = client.pull_requests(
      repository.full_name,
      state: state,
      sort: "updated",
      direction: "desc",
      per_page: limit
    )

    # Filter PRs by updated_at >= since
    prs.select { |pr| pr.updated_at >= since }
  end

  # List PRs for a user across all repositories with optional filters
  # Includes PRs created by the user AND PRs assigned to the user
  def list_user_pull_requests(username, filters: {}, limit: 50)
    # GitHub Search API doesn't support OR in a single query, so we need to make two queries:
    # 1. PRs created by the user (author:username)
    # 2. PRs assigned to the user (assignee:username)
    # Then merge and deduplicate the results
    
    prs_by_id = {} # Use hash to deduplicate by repo/number
    
    # Helper method to build base query parts
    build_base_query = lambda do |filters|
      query_parts = ["is:pr"]
      
      # Add state filter (default to open if not specified)
      state = filters[:state] || filters["state"] || "open"
      query_parts << "is:#{state}"
      
      # Add repository filter(s) if specified
      if filters[:repository] || filters["repository"]
        repo_value = filters[:repository] || filters["repository"]
        
        if repo_value.is_a?(Array)
          repo_value.each do |repo|
            query_parts << "repo:#{repo}"
          end
        else
          query_parts << "repo:#{repo_value}"
        end
      end
      
      # Add label filter if specified
      if filters[:label] || filters["label"]
        label = filters[:label] || filters["label"]
        query_parts << "label:#{label}"
      end
      
      # Add review status filter if specified
      if filters[:review_status] || filters["review_status"]
        review_status = filters[:review_status] || filters["review_status"]
        case review_status.to_s
        when "approved"
          query_parts << "review:approved"
        when "changes_requested"
          query_parts << "review:changes_requested"
        when "commented"
          query_parts << "review:commented"
        when "none"
          query_parts << "review:none"
        end
      end
      
      query_parts
    end
    
    # Helper method to execute search and fetch PRs
    fetch_prs_from_query = lambda do |query|
      Rails.logger.info("Searching GitHub with query: #{query}")
      
      begin
        results = client.search_issues(query, per_page: limit)
      rescue Octokit::UnprocessableEntity => e
        error_message = e.message
        Rails.logger.warn("GitHub search failed: #{error_message}")
        
        if error_message.include?("cannot be searched") || error_message.include?("do not have permission")
          repo_value = filters[:repository] || filters["repository"]
          if repo_value
            repo_list = repo_value.is_a?(Array) ? repo_value.join(", ") : repo_value
            raise ArgumentError, "Repository(ies) '#{repo_list}' not found or you don't have permission to access them"
          else
            raise ArgumentError, "Search failed: #{error_message}"
          end
        else
          raise ArgumentError, "Invalid search query: #{error_message}"
        end
      rescue Octokit::Error => e
        Rails.logger.error("GitHub API error: #{e.message}")
        raise ArgumentError, "GitHub API error: #{e.message}"
      end
      
      # Extract PR numbers and fetch full PR details
      results.items.each do |issue|
        url = issue.repository_url || issue.html_url
        url_parts = url.split("/")
        
        if url.include?("/repos/")
          repo_index = url_parts.index("repos")
          repo_full_name = "#{url_parts[repo_index + 1]}/#{url_parts[repo_index + 2]}"
        else
          github_index = url_parts.index("github.com") || url_parts.index("api.github.com")
          repo_full_name = "#{url_parts[github_index + 1]}/#{url_parts[github_index + 2]}"
        end
        
        pr_number = issue.number
        pr_key = "#{repo_full_name}##{pr_number}"
        
        # Skip if we already have this PR
        next if prs_by_id.key?(pr_key)
        
        begin
          pr = client.pull_request(repo_full_name, pr_number)
          prs_by_id[pr_key] = pr if pr
        rescue Octokit::NotFound, Octokit::Error => e
          Rails.logger.warn("Failed to fetch PR ##{pr_number} from #{repo_full_name}: #{e.message}")
          next
        end
      end
    end
    
    # Query 1: PRs created by the user
    base_query_parts = build_base_query.call(filters)
    author_query = (base_query_parts + ["author:#{username}"]).join(" ")
    fetch_prs_from_query.call(author_query)
    
    # Query 2: PRs assigned to the user (only if assignee filter is not already set)
    unless filters[:assignee] || filters["assignee"]
      assignee_query = (base_query_parts + ["assignee:#{username}"]).join(" ")
      fetch_prs_from_query.call(assignee_query)
    end
    
    # Return deduplicated PRs
    prs_by_id.values
  end

  # Merge a PR
  def merge_pull_request(repository, pr_number, merge_method: "merge", commit_title: nil, commit_message: nil)
    options = { merge_method: merge_method }
    options[:commit_title] = commit_title if commit_title
    options[:commit_message] = commit_message if commit_message

    client.merge_pull_request(repository.full_name, pr_number, options)
  end

  # Create a comment on a PR
  def create_comment(repository, pr_number, body)
    client.add_comment(repository.full_name, pr_number, body)
  end

  # Get comments on a PR
  def get_comments(repository, pr_number)
    client.issue_comments(repository.full_name, pr_number)
  end

  # Get review comments on a PR
  def get_review_comments(repository, pr_number)
    client.pull_request_comments(repository.full_name, pr_number)
  end

  # Get all reviews on a PR (approvals, changes requested, etc.)
  def get_reviews(repository, pr_number)
    client.pull_request_reviews(repository.full_name, pr_number)
  rescue Octokit::Error => e
    Rails.logger.error("Failed to get PR reviews: #{e.message}")
    []
  end

  # Get check runs and status for a PR
  def get_check_runs(repository, pr_number)
    pr_data = get_pull_request(repository, pr_number)
    return { state: "unknown", statuses: [] } unless pr_data

    head_sha = pr_data.head.sha
    
    # Get combined status (includes both statuses and check runs)
    combined_status = client.combined_status(repository.full_name, head_sha)
    
    {
      state: combined_status.state, # success, failure, pending, error
      statuses: combined_status.statuses.map do |status|
        {
          context: status.context,
          state: status.state,
          description: status.description,
          target_url: status.target_url,
          created_at: status.created_at
        }
      end
    }
  rescue Octokit::Error => e
    Rails.logger.error("Failed to get check runs: #{e.message}")
    { state: "unknown", statuses: [] }
  end

  # Get files changed in a PR
  def get_files(repository, pr_number)
    client.pull_request_files(repository.full_name, pr_number)
  end

  # Get file content from a repository
  # Returns the file content and metadata
  def get_file_content(repository, file_path, ref: nil)
    options = {}
    options[:ref] = ref if ref # ref can be a branch, tag, or commit SHA
    
    content = client.contents(repository.full_name, path: file_path, **options)
    
    # Content is base64 encoded, decode it
    decoded_content = Base64.decode64(content.content) if content.content
    
    {
      name: content.name,
      path: content.path,
      sha: content.sha,
      size: content.size,
      content: decoded_content,
      encoding: content.encoding,
      type: content.type, # "file", "dir", "symlink", "submodule"
      url: content.html_url,
      download_url: content.download_url
    }
  rescue Octokit::NotFound
    nil
  rescue Octokit::Error => e
    Rails.logger.error("Failed to get file content: #{e.message}")
    raise ArgumentError, "Failed to get file content: #{e.message}"
  end

  # Create a PR
  def create_pull_request(repository, title, head, base, body: nil)
    client.create_pull_request(
      repository.full_name,
      base,
      head,
      title,
      body
    )
  end

  # Approve a PR
  def approve_pull_request(repository, pr_number, body: nil)
    client.create_pull_request_review(
      repository.full_name,
      pr_number,
      event: "APPROVE",
      body: body
    )
  end

  # Trigger a workflow (run specs)
  def trigger_workflow(repository, workflow_file, ref: "main")
    # This requires the workflow_dispatch event
    # Note: This is a simplified version - you may need to adjust based on your CI setup
    client.post(
      "/repos/#{repository.full_name}/actions/workflows/#{workflow_file}/dispatches",
      { ref: ref }
    )
  end

  # Re-run failed jobs from a workflow run
  def rerun_failed_workflow(repository, run_id)
    client.post(
      "/repos/#{repository.full_name}/actions/runs/#{run_id}/rerun-failed-jobs"
    )
  end

  # Get workflow runs for a specific branch/PR
  def get_workflow_runs(repository, branch: nil, workflow_id: nil, per_page: 10)
    path = "/repos/#{repository.full_name}/actions/runs"
    params = { per_page: per_page }
    params[:branch] = branch if branch
    params[:workflow_id] = workflow_id if workflow_id
    
    query_string = params.map { |k, v| "#{k}=#{v}" }.join("&")
    path += "?#{query_string}" if query_string.present?
    
    response = client.get(path)
    # Octokit returns a Sawyer::Resource, access workflow_runs attribute
    runs = response.workflow_runs || []
    # Convert to array of hashes for easier handling
    runs.map do |run|
      {
        id: run.id,
        name: run.name,
        status: run.status,
        conclusion: run.conclusion,
        head_branch: run.head_branch,
        created_at: run.created_at
      }
    end
  rescue Octokit::Error => e
    Rails.logger.error("Failed to get workflow runs: #{e.message}")
    []
  end

  # Get repository info
  def get_repository(full_name)
    client.repository(full_name)
  end

  # Get user info
  def get_user_info
    client.user
  end

  # List all repositories the user has access to
  # Returns an array of repository full names (owner/repo-name)
  # Uses multiple methods to get all repos (affiliation + org-specific queries)
  def list_user_repositories(limit: 100)
    repos = []
    
    begin
      # Method 1: Use affiliation parameter to get repositories
      # - owner: repositories owned by the user
      # - collaborator: repositories where user is a collaborator
      # - organization_member: repositories in organizations the user is a member of
      Rails.logger.info("Fetching user repositories with affiliation: owner,collaborator,organization_member")
      
      client.repositories(
        affiliation: "owner,collaborator,organization_member",
        per_page: [limit, 100].min,
        type: "all",
        sort: "updated"
      ).each do |repo|
        repos << repo.full_name
        Rails.logger.debug("Found repository: #{repo.full_name}")
        break if repos.count >= limit
      end
      
      Rails.logger.info("Found #{repos.count} repositories via affiliation method")
      
      # Method 2: Also try to get repositories from specific organizations
      # This helps catch cases where affiliation doesn't work properly
      organizations = []
      if repos.count < limit
        begin
          Rails.logger.info("Fetching repositories from user's organizations...")
          organizations = client.organizations
          Rails.logger.info("User belongs to #{organizations.count} organizations: #{organizations.map(&:login).join(', ')}")
          
          organizations.each do |org|
            break if repos.count >= limit
            
            org_login = org.login
            Rails.logger.info("Fetching repositories from organization: #{org_login}")
            
            begin
              # Try to get repositories from this organization
              org_repos = client.organization_repositories(org_login, per_page: [limit - repos.count, 100].min, type: "all")
              org_repos.each do |repo|
                unless repos.include?(repo.full_name)
                  repos << repo.full_name
                  Rails.logger.debug("Found org repository: #{repo.full_name}")
                end
                break if repos.count >= limit
              end
              Rails.logger.info("Found #{org_repos.count} repositories in organization #{org_login}")
            rescue Octokit::Forbidden => e
              Rails.logger.warn("Forbidden: Cannot access repositories for organization #{org_login} - #{e.message}")
              # Continue with next org
            rescue Octokit::NotFound => e
              Rails.logger.warn("Not found: Organization #{org_login} not found - #{e.message}")
              # Continue with next org
            rescue Octokit::Error => e
              Rails.logger.warn("Error fetching repositories for organization #{org_login}: #{e.message}")
              # Continue with next org
            end
          end
        rescue Octokit::Error => e
          Rails.logger.warn("Failed to fetch organizations: #{e.message}")
          Rails.logger.warn(e.backtrace.join("\n"))
          # Continue even if org fetching fails
        end
      end
      
      Rails.logger.info("Total found: #{repos.count} repositories")
    rescue Octokit::Error => e
      Rails.logger.error("Failed to list user repositories: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      # Return what we have so far
    end
    
    repos.uniq
  end

  # Disambiguate a repository name by searching in user's accessible repositories
  # Returns the full repository name (owner/repo) if unique match found
  # Returns nil if no match, or raises ArgumentError if multiple matches
  def disambiguate_repository(repo_name)
    # If already in full format (owner/repo), return as is
    return repo_name if repo_name.include?("/")
    
    # Get all accessible repositories
    all_repos = list_user_repositories
    
    Rails.logger.info("🔍 Disambiguating repository '#{repo_name}' from #{all_repos.count} accessible repositories")
    
    # Find repositories matching the name (case-insensitive)
    matches = all_repos.select do |full_name|
      # Extract just the repo name part (after the last /)
      name_part = full_name.split("/").last
      name_part.downcase == repo_name.downcase
    end
    
    case matches.count
    when 0
      nil # No match found
    when 1
      matches.first # Unique match
    else
      # Multiple matches - raise error with list of matches
      matches_list = matches.join(", ")
      raise ArgumentError, "Multiple repositories named '#{repo_name}' found: #{matches_list}. Please specify the owner (e.g., 'owner/#{repo_name}')."
    end
  end

  private

  def client
    @client ||= begin
      github_token = @user.primary_github_token
      raise ArgumentError, "User has no GitHub token connected" unless github_token

      token = github_token.token
      raise ArgumentError, "GitHub token is invalid or expired" unless token

      Octokit::Client.new(access_token: token)
    end
  end
end
