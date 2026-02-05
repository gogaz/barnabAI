# frozen_string_literal: true

require "base64"

module Github
  class RepositoryOperations
    def initialize(client)
      @client = client
    end

    # Get file content from a repository
    def get_file_content(repository, file_path, ref: nil)
      options = {}
      options[:ref] = ref if ref
      
      content = @client.contents(repository.full_name, path: file_path, **options)
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
        @client.repositories(
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
            organizations = @client.organizations
            organizations.each do |org|
              break if repos.count >= limit
              
              begin
                org_repos = @client.organization_repositories(org.login, per_page: [limit - repos.count, 100].min, type: "all")
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
  end
end
