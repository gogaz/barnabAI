# frozen_string_literal: true

class Actions::MergePRAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "github_merge_pr"
  function_description "Merge a pull request. This action cannot be undone, always proceed with caution. Use this when the user explicitly requests to merge a PR."
  function_parameters({
                        type: "object",
                        properties: {
                          pr_number: {
                            type: "integer",
                            description: "The PR number to interact with. Can often be extracted from a URL or the user messages."
                          },
                          repository: {
                            type: "string",
                            description: "The repository in the format 'owner/repo'"
                          },
                          merge_method: {
                            type: "string",
                            enum: ["merge", "squash", "rebase"],
                            description: "The merge method to use. Defaults to 'squash' if not specified."
                          },
                          commit_title: {
                            type: "string",
                            description: "Optional custom title for the merge commit. If not provided, GitHub will generate a default title based on the PR title (preferred)."
                          },
                          commit_message: {
                            type: "string",
                            description: "Optional custom message for the merge commit."
                          }
                        },
                        required: ["pr_number", "repository"]
                      })

  def execute(parameters)
    pr_number = parameters[:pr_number]
    repository = parameters[:repository]
    merge_method = parameters[:merge_method] || "squash"
    commit_title = parameters[:commit_title]
    commit_message = parameters[:commit_message]

    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Repository is required" unless repository

    github_client.merge_pull_request(
      repository,
      pr_number,
      merge_method: merge_method,
      commit_title: commit_title,
      commit_message: commit_message || "Merged by BarnabAI"
    )

    "Merged <https://github.com/#{repository}/pull/#{pr_number}|PR ##{pr_number}> successfully."
  end
end
