# frozen_string_literal: true

class Actions::SinglePullRequestStatusUpdateAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "single_pull_request_status_update"
  function_description "When the user wants a status update to decide what are the next steps to move a PR forward, for example if there are blockers like failed checks or requested changes in reviews."
  function_parameters({
    type: "object",
    properties: {
      pr_number: {
        type: "integer",
        description: "The PR number from the list of messages. Can often be extracted from a URL sent by the agent or the user or if the user mentions a PR number."
      },
      repository: {
        type: "string",
        description: "The Github repository full name including owner (ideal format: 'owner/repo-name'). Can often be extracted from a URL sent by the agent or the user or if the user mentions a PR number."
      }
    },
    required: ["pr_number", "repository"]
  })

  PROMPT = <<~PROMPT.squish
    The user asks for a status update on a PR, my answer should focus on providing clear and actionable insights based on the current state of the PR, including any reviews, comments, workflow results and mergeability of the PR. 
    I will:
      - Summarize Status: Briefly state the PR context and current progress (CI, reviews, recent activity).
      - Highlight References: List all relevant external links found (JIRA, Sentry, Notion, etc.).
      - Identify Blockers: Pinpoint failed workflows or human-requested changes. I will prioritize human feedback over bot comments.
      - Confirm Mergeability: Detail whether the PR is technically ready to be merged.
      - Drive Action: Suggest the next logical step (e.g., "Ping the maintainer," "Fix the linting error," or "Draft a help request").
    I will avoid repeating information already present in our conversation history.
  PROMPT

  # Returns an array of messages
  def execute(parameters)
    pr_number = parameters[:pr_number]
    raise ArgumentError, "PR number is required" unless pr_number

    repository = parameters[:repository]
    raise ArgumentError, "Repository information is required. Please specify the repository (e.g., 'owner/repo-name')." unless repository

    pr_data = github_client.get_pull_request(repository, pr_number)
    raise ArgumentError, "PR ##{pr_number} not found in #{repository}" unless pr_data

    context.add_assistant_message(PROMPT)
    function_args = { repository: repository, pr_number: pr_number }
    context.add_function_call("github_get_pull_request", function_args, pr_data)
    context.add_function_call("github_get_pull_comments", function_args, github_client.get_comments(repository, pr_number))
    context.add_function_call("github_get_pull_reviews", function_args, github_client.get_reviews(repository, pr_number))
    context.add_function_call("github_get_pull_check_runs", function_args, github_client.get_check_runs(repository, pr_data[:head][:sha]))
    files = github_client.get_files(repository, pr_number)
    context.add_function_call("github_get_pull_impacted_teams", function_args, Github::CodeOwnersMatcher.new(github_client, repository).determine_impacted_teams(files, ref: pr_data.dig(:base, :ref)))

    ai_provider.chat_completion(
      context.build_prompt,
      response_format: :text
    )
  end
end
