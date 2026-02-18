# frozen_string_literal: true

class Actions::ClosePRAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "github_close_pr"
  function_description "Close a pull request without merging. Use this when the user wants to close a PR."
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
                          message: {
                            type: "string",
                            description: "Optional reason for closing the PR."
                          },
                        },
                        required: ["pr_number", "repository"]
                      })

  def execute(parameters)
    pr_number = parameters[:pr_number]
    raise ArgumentError, "PR number is required" unless pr_number

    repository = parameters[:repository]
    raise ArgumentError, "Repository is required" unless repository

    message = parameters[:message]
    client = Octokit::Client.new(access_token: @user.primary_github_token.token)
    comment_response = client.add_comment(repository, pr_number, message) if message.present?
    client.close_pull_request(repository, pr_number)

    url = comment_response&.html_url || "https://github.com/#{repository}/pull/#{pr_number}"
    "Closed <#{url}|PR ##{pr_number}> successfully."
  end
end
