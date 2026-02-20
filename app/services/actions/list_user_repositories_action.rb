# frozen_string_literal: true

class Actions::ListUserRepositoriesAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "github_user_repositories"
  function_description "List all GitHub repositories the user has access to (owned, collaborator, or organization member). Returns a list of repository names in 'owner/repo' format."
  function_parameters({
                        type: "object",
                        properties: {},
                        required: []
                      })

  def execute(_parameters)
    github_client.list_user_repositories(limit: 100)
  end
end

