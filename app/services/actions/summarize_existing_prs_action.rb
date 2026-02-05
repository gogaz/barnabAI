# frozen_string_literal: true

class Actions::SummarizeExistingPrsAction < Actions::BaseAction
  include PrFormatterConcern

  def execute(parameters)
    # Get user's GitHub username
    github_username = @user.primary_github_token&.github_username
    raise ArgumentError, "User has no GitHub token connected" unless github_username

    # Extract filters from parameters (default to open if not specified)
    filters = parameters[:filters] || parameters["filters"] || { state: "open" }
    
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
end
