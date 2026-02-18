# frozen_string_literal: true

class Actions::GetPRDetailsAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "github_get_pr_details"
  function_description "Get detailed information about a pull request including title, state, reviews, CI checks, and discussions. Use this when you need to analyze or provide information about a PR."
  function_parameters({
                        type: "object",
                        properties: {
                          pr_number: {
                            type: "integer",
                            description: "The PR number to fetch details for. Can often be extracted from a URL or the user messages."
                          },
                          repository: {
                            type: "string",
                            description: "The repository in the format 'owner/repo'"
                          }
                        },
                        required: ["pr_number", "repository"]
                      })

  def execute(parameters)
    pr_number = parameters[:pr_number]
    repository = parameters[:repository]

    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Repository is required" unless repository

    fetcher = Github::PullRequestFetcher.new(user)
    pr_details = fetcher.call(repository, pr_number)

    raise "Pull request ##{pr_number} not found in repository #{repository}" unless pr_details

    pr_details
  end
end

