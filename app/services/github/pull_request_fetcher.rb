# frozen_string_literal: true

class Github::PullRequestFetcher
  include Github::HasGraphqlQuery

  PULL_REQUEST_FIELDS = <<~FIELDS.strip
    title
    url
    body
    state
    isDraft
    createdAt
    author { login }
    assignees(first: 10) { nodes { login } }
    reviewRequests(last: 10) {
      nodes { requestedReviewer { ... on User { login } ... on Team { name } } }
    }
    reviews(last: 20) {
      nodes {
        author { login }
        state
        createdAt
        body
      }
    }
    reviewThreads(last: 20) {
      nodes {
        isResolved
        isOutdated
        path
        comments(last: 5) {
          nodes {
            author { login, __typename }
            body
            diffHunk
            createdAt
          }
        }
      }
    }
    comments(last: 50) {
      nodes {
        author {
          login
          __typename
        }
        body
        createdAt
      }
    }
    commits(last: 1) {
      nodes {
        commit {
          statusCheckRollup {
            contexts(last: 50) {
              nodes {
                ... on CheckRun { name, conclusion, title, summary, detailsUrl }
                ... on StatusContext { context, state, description }
              }
            }
          }
        }
      }
    }
  FIELDS

  NODES_QUERY = <<~GRAPHQL
    query($ids: [ID!]!) {
      nodes(ids: $ids) {
        ... on PullRequest {
          #{PULL_REQUEST_FIELDS}
        }
      }
    }
  GRAPHQL

  attr_reader :github_token

  def initialize(user)
    @github_token = user.primary_github_token.token
  end

  graphql_query :single_pr, <<~GRAPHQL
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          #{PULL_REQUEST_FIELDS}
        }
      }
    }
  GRAPHQL

  graphql_query :nodes, NODES_QUERY

  def call(repo_full_name, pr_number)
    owner, name = repo_full_name.split('/')

    raw_response = run_graphql(:single_pr, owner: owner, name: name, number: pr_number.to_i)
    pr_data = raw_response.dig(:repository, :pullRequest)

    return nil unless pr_data

    parse_pr_data(pr_data)
  end

  # Fetch multiple pull requests by their global node IDs (from REST search node_id or GraphQL id)
  # Single GraphQL query, no iterations. Returns parsed PRs (same format as call). Max 100 IDs.
  def call_many(node_ids)
    ids = Array(node_ids).map(&:to_s).reject(&:blank?).uniq.first(100)
    return [] if ids.empty?

    raw_response = run_graphql(:nodes, { ids: ids })
    nodes = raw_response[:nodes] || []
    nodes.filter_map { |node| parse_pr_data(node) if node.present? }
  end

  private

  def parse_pr_data(pr)
    {
      meta: {
        title: pr[:title],
        url: pr[:url],
        author: pr.dig(:author, :login),
        state: pr[:isDraft] ? "DRAFT" : pr[:state],
        assignees: pr.dig(:assignees, :nodes)&.map { |n| n[:login] } || [],
        reviewers: extract_reviewers(pr)
      },
      description: pr[:body],
      ci_checks: extract_ci(pr),
      discussions: {
        global: extract_reviews(pr),
        code: extract_threads(pr)
      }
    }
  end

  def extract_reviewers(pr)
    pr.dig(:reviewRequests, :nodes)&.map { |n|
      r = n[:requestedReviewer]
      r[:login] || r[:name]
    } || []
  end

  def extract_ci(pr)
    nodes = pr.dig(:commits, :nodes, 0, :commit, :statusCheckRollup, :contexts, :nodes) || []
    nodes.map do |n|
      {
        name: n[:name] || n[:context],
        status: n[:conclusion] || n[:state],
        details: n[:summary] || n[:title] || n[:description],
        url: n[:detailsUrl]
      }
    end
  end

  def extract_reviews(pr)
    (pr.dig(:reviews, :nodes) || []).reject { |r| r[:body].blank? }.map do |r|
      { user: r.dig(:author, :login), verdict: r[:state], content: r[:body] }
    end
  end

  def extract_threads(pr)
    (pr.dig(:reviewThreads, :nodes) || []).filter_map do |thread|
      next if thread[:isOutdated]
      comment = thread.dig(:comments, :nodes, 0)
      next if !comment || comment.dig(:author, :__typename) == 'Bot'

      {
        file: thread[:path],
        is_resolved: thread[:isResolved],
        user: comment.dig(:author, :login),
        content: comment[:body],
        code: comment[:diffHunk]
      }
    end
  end

  def extract_general_comments(pr)
    (pr.dig(:comments, :nodes) || []).map do |comment|
      {
        user: comment.dig(:author, :login),
        content: comment[:body],
        created_at: comment[:createdAt],
        type: comment.dig(:author, :__typename)
      }
    end
  end
end