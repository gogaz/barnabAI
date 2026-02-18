# frozen_string_literal: true

class Actions::RespondToCommentAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "respond_to_comment"
  function_description "Reply to a review comment on a pull request. Use this when the user wants to respond to a specific comment."
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
                          comment_id: {
                            type: "integer",
                            description: "The ID of the comment to reply to."
                          },
                        },
                        required: ["pr_number", "repository", "message", "comment_id"]
                      })

  def execute(parameters)
    comment_id = parameters[:comment_id]
    message = parameters[:message]
    repository = parameters[:repository]
    pr_number = parameters[:pr_number]

    raise ArgumentError, "Comment ID is required" unless comment_id
    raise ArgumentError, "Response body is required" unless message
    raise ArgumentError, "Repository is required" unless repository

    github_client.create_pull_request_comment_reply(
      repository,
      pr_number,
      message,
      comment_id
    )

    "Replied to comment ##{comment_id}"
  end
end

