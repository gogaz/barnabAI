# frozen_string_literal: true

class Actions::SummarizeMyCurrentWorkAction < Actions::BaseAction
  include Actions::HasFunctionMetadata

  function_code "slack_summarize_my_current_work"
  function_description "Provides the user with a clear list of pull requests on which they are either owner, assigned or requested review. User can optionally specify filters. Results are directly sent to the user without further processing."
  function_stops_reflexion? true
  function_parameters({
    type: "object",
    properties: {
        repository: {
          type: "array",
          items: { type: "string" },
          description: "Filter PRs by repository or repositories (format: owner/repo-name). Can be a single repository or multiple repositories. Defaults to all repositories the user has access to."
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
    required: [],
  })

  # Returns an array of messages (one per PR)
  def execute(filters = {})
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

    channel = user.slack_user_id
    return build_zero_pull_requests_message.send!(channel:) if total.zero?

    messages = [
      build_pull_requests_section_messages(prs_owned, 15),
      build_pull_requests_section_messages(prs_assigned, 15),
      build_pull_requests_section_messages(prs_review_requested, 15)
    ].flatten
    messages.each do |message|
      message.send!(channel:)
    end
    nil
  end

  private

  def build_pull_requests_section_messages(pull_requests, max_count)
    count = pull_requests.count

    return build_zero_pull_requests_message if count.zero?

    messages = pull_requests.first(max_count).map do |pr|
      opened_since = ActionController::Base.helpers.distance_of_time_in_words(Time.current, pr.created_at)
      stale_since = ActionController::Base.helpers.distance_of_time_in_words(Time.current, pr.updated_at)

      Slack::MessageBuilder.new(text: "PR ##{pr.number}: #{pr.title}")
        .add_section_block("*(##{pr.number}) #{Slack::Messages::Formatting.url_link(pr.title, pr.html_url)}*")
        .add_context_block(
          ":github: Repo: *#{pr.base.repo.full_name}*",
          "👤 Author: *#{pr.user.login}*",
          "Changes: 🟢 +#{pr.additions} | 🔴 -#{pr.deletions}",
          "`#{pr.base.ref}` ⬅️ `#{pr.head.ref}`",
          "🕒 #{opened_since}", ":zzz: #{stale_since}"
        )
    end

    return messages + Slack::MessageBuilder.new.add_context_block(":pencil: Only showing #{max_count}/#{count} results.") if count > max_count
    messages
  end

  def build_zero_pull_requests_message
    Slack::MessageBuilder.new.add_context_block("Nothing to show here :sparkles:")
  end
end
