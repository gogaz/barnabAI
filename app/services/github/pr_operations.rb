# frozen_string_literal: true

module Github
  class PrOperations
    def initialize(client)
      @client = client
    end

    # Get a specific PR
    def get_pull_request(repository, pr_number)
      @client.pull_request(repository.full_name, pr_number)
    rescue Octokit::NotFound
      nil
    end

    # List PRs for a repository
    def list_pull_requests(repository, state: "open", limit: 10)
      @client.pull_requests(repository.full_name, state: state, per_page: limit)
    end

    # List PRs for a repository with since parameter (filters by updated_at)
    def list_pull_requests_since(repository, since:, state: "all", limit: 100)
      prs = @client.pull_requests(
        repository.full_name,
        state: state,
        sort: "updated",
        direction: "desc",
        per_page: limit
      )

      prs.select { |pr| pr.updated_at >= since }
    end

    # List PRs for a user across all repositories with optional filters
    def list_user_pull_requests(username, filters: {}, limit: 50)
      prs_by_id = {}
      
      build_base_query = lambda do |filters|
        query_parts = ["is:pr"]
        state = filters[:state] || filters["state"] || "open"
        query_parts << "is:#{state}"
        
        if filters[:repository] || filters["repository"]
          repo_value = filters[:repository] || filters["repository"]
          if repo_value.is_a?(Array)
            repo_value.each { |repo| query_parts << "repo:#{repo}" }
          else
            query_parts << "repo:#{repo_value}"
          end
        end
        
        if filters[:label] || filters["label"]
          label = filters[:label] || filters["label"]
          query_parts << "label:#{label}"
        end
        
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
      
      fetch_prs_from_query = lambda do |query|
        Rails.logger.info("Searching GitHub with query: #{query}")
        
        begin
          results = @client.search_issues(query, per_page: limit)
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
        
        results.items.each do |issue|
          url = issue.repository_url || issue.html_url
          url_parts = url.split("/")
          
          repo_full_name = if url.include?("/repos/")
            "#{url_parts[url_parts.index("repos") + 1]}/#{url_parts[url_parts.index("repos") + 2]}"
          else
            github_index = url_parts.index("github.com") || url_parts.index("api.github.com")
            "#{url_parts[github_index + 1]}/#{url_parts[github_index + 2]}"
          end
          
          pr_number = issue.number
          pr_key = "#{repo_full_name}##{pr_number}"
          
          next if prs_by_id.key?(pr_key)
          
          begin
            pr = @client.pull_request(repo_full_name, pr_number)
            prs_by_id[pr_key] = pr if pr
          rescue Octokit::NotFound, Octokit::Error => e
            Rails.logger.warn("Failed to fetch PR ##{pr_number} from #{repo_full_name}: #{e.message}")
            next
          end
        end
      end
      
      base_query_parts = build_base_query.call(filters)
      author_query = (base_query_parts + ["author:#{username}"]).join(" ")
      fetch_prs_from_query.call(author_query)
      
      unless filters[:assignee] || filters["assignee"]
        assignee_query = (base_query_parts + ["assignee:#{username}"]).join(" ")
        fetch_prs_from_query.call(assignee_query)
      end
      
      prs_by_id.values
    rescue Octokit::UnprocessableEntity => e
      Rails.logger.error("Invalid GitHub search query: #{e.message}")
      raise ArgumentError, "Invalid search query: #{e.message}"
    rescue Octokit::Error => e
      Rails.logger.error("Failed to list user PRs: #{e.message}")
      raise ArgumentError, "Failed to list PRs: #{e.message}"
    end

    # Merge a PR
    def merge_pull_request(repository, pr_number, merge_method: "merge", commit_title: nil, commit_message: nil)
      options = { merge_method: merge_method }
      options[:commit_title] = commit_title if commit_title
      options[:commit_message] = commit_message if commit_message

      @client.merge_pull_request(repository.full_name, pr_number, options)
    end

    # Create a comment on a PR
    def create_comment(repository, pr_number, body)
      @client.add_comment(repository.full_name, pr_number, body)
    end

    # Get comments on a PR
    def get_comments(repository, pr_number)
      @client.issue_comments(repository.full_name, pr_number)
    end

    # Get review comments on a PR
    def get_review_comments(repository, pr_number)
      @client.pull_request_comments(repository.full_name, pr_number)
    end

    # Get all reviews on a PR (approvals, changes requested, etc.)
    def get_reviews(repository, pr_number)
      @client.pull_request_reviews(repository.full_name, pr_number)
    rescue Octokit::Error => e
      Rails.logger.error("Failed to get PR reviews: #{e.message}")
      []
    end

    # Get check runs and status for a PR
    def get_check_runs(repository, pr_number)
      pr_data = get_pull_request(repository, pr_number)
      return { state: "unknown", statuses: [] } unless pr_data

      head_sha = pr_data.head.sha
      combined_status = @client.combined_status(repository.full_name, head_sha)
      
      {
        state: combined_status.state,
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
      @client.pull_request_files(repository.full_name, pr_number)
    end

    # Create a PR
    def create_pull_request(repository, title, head, base, body: nil)
      @client.create_pull_request(
        repository.full_name,
        base,
        head,
        title,
        body
      )
    end

    # Approve a PR
    def approve_pull_request(repository, pr_number, body: nil)
      @client.create_pull_request_review(
        repository.full_name,
        pr_number,
        event: "APPROVE",
        body: body
      )
    end
  end
end
