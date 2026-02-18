# frozen_string_literal: true

class Actions::CreateCommentAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "github_add_new_comment_on_pr"
  function_description "Create a new comment on a pull request. Use this when the user wants to add a general comment to the PR discussion."
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
                            description: "The text to send."
                          },
                        },
                        required: ["pr_number", "repository", "message"]
                      })

  def execute(parameters)
    message = parameters[:message]
    pr_number = parameters[:pr_number]
    repository = parameters[:repository]

    raise ArgumentError, "Message is required" unless message
    raise ArgumentError, "PR number is required" unless pr_number
    raise ArgumentError, "Repository is required" unless repository

    client = Octokit::Client.new(access_token: @user.primary_github_token.token)
    response = client.add_comment(repository, pr_number, message)

    "Comment posted to #{response.html_url}"
  end
end

