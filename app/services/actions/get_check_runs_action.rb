# frozen_string_literal: true

class Actions::GetCheckRunsAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "github_get_check_runs"
  function_description "Get the CI check runs for a pull request or a specific commit SHA. Returns each check's name, status, conclusion, and details URL. Use this when the user asks about CI status, failing checks, or test results on a PR."
  function_parameters({
    type: "object",
    properties: {
      pr_number: {
        type: "integer",
        description: "The PR number to fetch check runs for. Used to resolve the HEAD commit SHA automatically."
      },
      repository: {
        type: "string",
        description: "The repository in the format 'owner/repo'."
      },
      sha: {
        type: "string",
        description: "Optional specific commit SHA to fetch check runs for. If omitted, the HEAD SHA of the given PR is used."
      }
    },
    required: ["repository"]
  })

  def execute(parameters)
    repository = parameters[:repository]
    pr_number  = parameters[:pr_number]
    sha        = parameters[:sha]

    raise ArgumentError, "Repository is required" if repository.blank?
    raise ArgumentError, "Either pr_number or sha is required" unless pr_number.present? || sha.present?

    fetcher = Github::CheckRunsFetcher.new(user)

    if sha.present?
      fetcher.call_by_sha(repository, sha)
    else
      fetcher.call_by_pr(repository, pr_number)
    end
  end
end
