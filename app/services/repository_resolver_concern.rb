# frozen_string_literal: true

module RepositoryResolverConcern
  extend ActiveSupport::Concern

  private

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
end
