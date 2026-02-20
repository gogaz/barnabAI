# frozen_string_literal: true

require "octokit"
require "base64"

module Github
  class Client
    def initialize(user)
      @user = user
    end

    # Search for pull requests using GitHub search API (returns full PR objects, one API call per result)
    def search_pull_requests(query, limit: 50)
      results = client.search_issues(query, per_page: limit)
      results.items.filter_map do |issue|
        repo_full_name = issue.repository&.full_name || extract_repo_from_url(issue.repository_url || issue.html_url)
        next unless repo_full_name

        client.pull_request(repo_full_name, issue.number)
      end
    end

    # Search for pull requests using GitHub search API (single API call, no per-result fetches)
    # Returns minimal PR info from the search response: repository, number, title, html_url, state, author, dates
    def search_pull_requests_list(query, limit: 50)
      results = client.search_issues(query, per_page: limit)
      results.items.filter_map do |issue|
        next unless issue.pull_request # Skip if it's an issue, not a PR

        repo_full_name = issue.repository&.full_name
        repo_full_name ||= extract_repo_from_url(issue.repository_url || issue.html_url)

        {
          repository: repo_full_name,
          number: issue.number,
          title: issue.title,
          html_url: issue.html_url,
          node_id: issue.node_id,
          state: issue.state,
          author: issue.user&.login,
          created_at: issue.created_at,
          updated_at: issue.updated_at
        }
      end
    end

    # Get a specific PR
    def get_pull_request(repository, pr_number)
      client.pull_request(repository, pr_number)
    rescue Octokit::NotFound
      nil
    end

    # List PRs for a repository
    def list_pull_requests(repository, state: "open", limit: 10)
      client.pull_requests(repository.full_name, state: state, per_page: limit)
    end

    # List PRs for a repository with since parameter (filters by updated_at)
    def list_pull_requests_since(repository, since:, state: "all", limit: 100)
      prs = client.pull_requests(
        repository.full_name,
        state: state,
        sort: "updated",
        direction: "desc",
        per_page: limit
      )

      prs.select { |pr| pr.updated_at >= since }
    end

    # Merge a pull request
    def merge_pull_request(repository, pr_number, merge_method: "merge", commit_title: nil, commit_message: nil)
      options = { merge_method: merge_method }
      options[:commit_title] = commit_title if commit_title

      client.merge_pull_request(repository, pr_number, commit_message || '', options)
    end

    # Get comments on a PR
    def get_comments(repository, pr_number)
      client.issue_comments(repository, pr_number)
    end

    # Reply to a pull request comment
    def create_pull_request_comment_reply(repository, pr_number, body, comment_id)
      client.create_pull_request_comment_reply(repository, comment_id, body)
    end

    # Get all reviews on a PR (approvals, changes requested, etc.)
    def get_reviews(repository, pr_number)
      client.pull_request_reviews(repository, pr_number)
    rescue Octokit::Error => e
      Rails.logger.error("Failed to get PR reviews: #{e.message}")
      []
    end

    # Get check runs and status for a commit SHA
    def get_check_runs(repository, sha)
      check_runs = client.check_runs_for_ref(repository, sha)
      {
        total_count: check_runs.total_count,
        check_runs: check_runs.check_runs.map do |run|
          {
            name: run.name,
            status: run.status,
            conclusion: run.conclusion,
            details_url: run.details_url,
            started_at: run.started_at,
            completed_at: run.completed_at
          }
        end
      }
    rescue Octokit::Error => e
      Rails.logger.error("Failed to get check runs: #{e.message}")
      { total_count: 0, check_runs: [] }
    end

    # Get files changed in a PR
    def get_files(repository, pr_number)
      client.pull_request_files(repository, pr_number)
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
      runs = response.workflow_runs || []

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

    # Get file content from a repository
    def get_file_content(repository, file_path, ref: nil)
      options = {}
      options[:ref] = ref if ref

      content = client.contents(repository.full_name, path: file_path, **options)
      decoded_content = Base64.decode64(content.content) if content.content

      {
        name: content.name,
        path: content.path,
        sha: content.sha,
        size: content.size,
        content: decoded_content,
        encoding: content.encoding,
        type: content.type,
        url: content.html_url,
        download_url: content.download_url
      }
    rescue Octokit::NotFound
      nil
    rescue Octokit::Error => e
      Rails.logger.error("Failed to get file content: #{e.message}")
      raise ArgumentError, "Failed to get file content: #{e.message}"
    end

    # List repositories accessible to the user
    def list_user_repositories(limit: 100)
      repos = []

      begin
        client.repositories(
          affiliation: "owner,collaborator,organization_member",
          per_page: [limit, 100].min,
          type: "all",
          sort: "updated"
        ).each do |repo|
          repos << repo.full_name
          break if repos.count >= limit
        end

        if repos.count < limit
          begin
            organizations = client.organizations
            organizations.each do |org|
              break if repos.count >= limit

              begin
                org_repos = client.organization_repositories(org.login, per_page: [limit - repos.count, 100].min, type: "all")
                org_repos.each do |repo|
                  repos << repo.full_name unless repos.include?(repo.full_name)
                  break if repos.count >= limit
                end
              rescue Octokit::Forbidden, Octokit::NotFound, Octokit::Error
                # Continue with next org
              end
            end
          rescue Octokit::Error
            # Continue even if org fetching fails
          end
        end
      rescue Octokit::Error => e
        Rails.logger.error("Failed to list user repositories: #{e.message}")
      end

      repos.uniq
    end

    # Disambiguate repository name (find full name from short name)
    def disambiguate_repository(repo_name)
      # If already in full format (owner/repo), return as is
      return repo_name if repo_name.include?("/")

      all_repos = list_user_repositories

      # Find repositories matching the name (case-insensitive)
      matches = all_repos.select do |full_name|
        name_part = full_name.split("/").last
        name_part.downcase == repo_name.downcase
      end

      case matches.count
      when 0
        nil
      when 1
        matches.first
      else
        matches_list = matches.join(", ")
        raise ArgumentError, "Multiple repositories named '#{repo_name}' found: #{matches_list}. Please specify the owner (e.g., 'owner/#{repo_name}')."
      end
    end

    private

    def extract_repo_from_url(url)
      return nil if url.blank?

      url_parts = url.split("/")
      if url.include?("/repos/")
        "#{url_parts[url_parts.index("repos") + 1]}/#{url_parts[url_parts.index("repos") + 2]}"
      else
        github_index = url_parts.index("github.com") || url_parts.index("api.github.com")
        return nil unless github_index

        "#{url_parts[github_index + 1]}/#{url_parts[github_index + 2]}"
      end
    end

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
end
