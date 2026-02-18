# frozen_string_literal: true

class Actions::SummarizeMyCurrentWorkAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "slack_summarize_my_current_work"
  function_description "Provides the user with a clear list of pull requests on which they are either owner, assigned or requested review. User can optionally specify filters. Results are directly sent to the user without further processing."
  function_stops_reflexion? true
  function_parameters({
    type: "object",
    properties: {
      filters: {
        type: "object",
        properties: {
          repository: {
            type: "array",
            items: { type: "string" },
            description: "Filter PRs by repository or repositories (format: owner/repo-name). Can be a single repository or multiple repositories. Only include if user specifically mentions repositories."
          },
          label: {
            type: "string",
            description: "Filter PRs by label. Only include if user specifically mentions a label, title, name, ..."
          },
          created: {
            type: "string",
            description: "Filter by creation date using ISO 8601 format and qualifiers (e.g., '>2023-01-01', '2023-01-01..2023-12-31')."
          },
          updated: {
            type: "string",
            description: "Filter by last updated date using ISO 8601 format and qualifiers (e.g., '>2023-01-01', '2023-01-01..2023-12-31'). Include if user specifically mentions recency or staleness."
          },
          sort: {
            type: "string",
            enum: ["created", "updated", "comments", "long-running"],
            description: "The field to sort the results by. Default: created"
          },
          order: {
            type: "string",
            enum: ["desc", "asc"],
            description: "The direction of the sort. Default: desc"
          }
        },
        description: "Optional filters to apply to the PR search. Only include filters that the user explicitly mentions in their request."
      }
    }
  })

  # Returns an array of messages (one per PR)
  def execute(parameters)
    filters = parameters[:filters] || {}
    filter_query = Github::QueryBuilder.to_query(filters)

    prs_owned = github_client.search_pull_requests(
      Github::QueryBuilder.new.where(filter_query).where("is:pr is:open author:@me").build
    )
    prs_assigned = github_client.search_pull_requests(
      Github::QueryBuilder.new.where(filter_query).where("is:pr is:open assignee:@me").not("author:@me").build
    )
    prs_review_requested = github_client.search_pull_requests(
      Github::QueryBuilder.new.where(filter_query).where("is:pr is:open review-requested:@me").not("author:@me").not("assignee:@me").build
    )

    prs = prs_owned + prs_assigned + prs_review_requested
    total = prs.flatten.count

    return build_zero_pull_requests_message(Slack::MessageBuilder.new(text: "Nothing to report!")) if total.zero?

    [
      build_pull_requests_section_messages(prs_owned, ":ship: Your PRs", 15),
      build_pull_requests_section_messages(prs_assigned, ":handshake: PRs you've been assigned to", 15),
      build_pull_requests_section_messages(prs_review_requested, ":face_with_monocle: Review Requested", 15)
    ].flatten
  end

  private

  def build_pull_requests_section_messages(pull_requests, title, max_count)
    count = pull_requests.count

    first_message = Slack::MessageBuilder.new(text: "*#{title}* (#{count})")
    first_message.add_header_block("#{title} #{count > 1 ? "(#{count})" : ""}")
    return build_zero_pull_requests_message(first_message) if count.zero?

    first_message.add_context_block(":pencil: Only showing #{max_count}/#{count} results.") if count > max_count

    [first_message] + pull_requests.first(max_count).map do |pr|
      opened_since = ActionController::Base.helpers.distance_of_time_in_words(Time.current, pr.created_at)
      stale_since = ActionController::Base.helpers.distance_of_time_in_words(Time.current, pr.updated_at)

      Slack::MessageBuilder.new(text: "PR ##{pr.number}: #{pr.title}")
        .add_section_block("*(##{pr.number}) #{Slack::Messages::Formatting.url_link(pr.title, pr.html_url)}*")
        .add_context_block(":github: Repo: *#{pr.base.repo.full_name}*")
        .add_section_block(fields: ["👤 Author: *#{pr.user.login}*", "Changes: 🟢 +#{pr.additions} | 🔴 -#{pr.deletions}"])
        .add_section_block("`#{pr.base.ref}` ⬅️ `#{pr.head.ref}`")
        .add_context_block("🕒 #{opened_since}", ":zzz: #{stale_since}")
    end
  end

  def build_zero_pull_requests_message(title_message)
    title_message.add_context_block("Nothing to show here :sparkles:")
    title_message
  end
end
