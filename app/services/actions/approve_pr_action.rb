# frozen_string_literal: true

class Actions::ApprovePRAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "github_approve_pr"
  function_description "Approve a pull request review. Use this when the user wants to approve a PR, either by explicitly saying 'approve' or by expressing agreement/support for the changes in the PR."
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
                            description: "Optional reason for approving the PR."
                          },
                        },
                        required: ["pr_number", "repository"]
                      })

  def execute(parameters)
    pr_number = parameters[:pr_number]
    body = parameters[:message]
    raise ArgumentError, "PR number is required" unless pr_number

    repository = parameters[:repository]
    raise ArgumentError, "Repository is required" unless repository

    client = Octokit::Client.new(access_token: @user.primary_github_token.token)
    response = client.create_pull_request_review(
      repository,
      pr_number,
      event: "APPROVE",
      body: body
    )

    "Approved <#{response.html_url}|PR ##{pr_number}> successfully."
  end
end
