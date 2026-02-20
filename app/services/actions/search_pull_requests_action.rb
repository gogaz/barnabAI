# frozen_string_literal: true

class Actions::SearchPullRequestsAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "github_search_pull_requests"
  function_description "Search for pull requests across GitHub using GitHub's search syntax, limited to 50 results. Returns minimal info: repository, number, title, html_url, node_id, state, author, created_at, updated_at."
  function_parameters({
    type: "object",
    properties: {
      query: {
        type: "string",
        description: <<~PARAM.strip
          The GitHub search query string. Build the query from the user's intent using these qualifiers (combine with spaces):
          - is:open, is:closed, is:merged, is:draft
          - author:USERNAME or author:@me (PRs created by user)
          - repo:owner/repo or org:ORGNAME (scope to repository or organization)
          - assignee:USERNAME or assignee:@me
          - review-requested:USERNAME or user-review-requested:@me (awaiting their review)
          - reviewed-by:USERNAME (they have reviewed)
          - label:LABEL_NAME
          - created:>YYYY-MM-DD, updated:>YYYY-MM-DD, merged:>YYYY-MM-DD (date filters)
          - in:title, in:body (search text in title or body)
          Examples: "is:pr is:open author:@me OR assignee:@me", "is:pr repo:rails/rails label:bug", "is:pr assignee:@me updated:>2024-01-01"
        PARAM
      }
    },
    required: ["query"]
  })

  def execute(parameters)
    query = parameters[:query]
    raise ArgumentError, "Search query is required" if query.blank?

    # Ensure we're searching PRs, not issues
    search_query = query.include?("is:pr") ? query : "is:pr #{query}"

    github_client.search_pull_requests_list(search_query, limit: 50)
  end
end
