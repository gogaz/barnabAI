# frozen_string_literal: true

class Github::CheckRunsFetcher
  include Github::HasGraphqlQuery

  CHECK_RUN_FIELDS = <<~FIELDS.strip
    name
    status
    conclusion
    detailsUrl
    startedAt
    completedAt
    annotations(first: 50) {
      nodes {
        path
        location {
          start { line }
          end { line }
        }
        annotationLevel
        message
        title
        rawDetails
      }
    }
  FIELDS

  CHECK_SUITES_FRAGMENT = <<~FRAGMENT.strip
    checkSuites(first: 20) {
      nodes {
        app { name }
        checkRuns(first: 50) {
          nodes {
            #{CHECK_RUN_FIELDS}
          }
        }
      }
    }
  FRAGMENT

  graphql_query :by_pr, <<~GRAPHQL
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          commits(last: 1) {
            nodes {
              commit {
                #{CHECK_SUITES_FRAGMENT}
              }
            }
          }
        }
      }
    }
  GRAPHQL

  graphql_query :by_sha, <<~GRAPHQL
    query($owner: String!, $name: String!, $sha: String!) {
      repository(owner: $owner, name: $name) {
        object(expression: $sha) {
          ... on Commit {
            #{CHECK_SUITES_FRAGMENT}
          }
        }
      }
    }
  GRAPHQL

  def initialize(user)
    @github_token = user.primary_github_token.token
  end

  def call_by_pr(repo_full_name, pr_number)
    owner, name = repo_full_name.split("/")
    response = run_graphql(:by_pr, owner: owner, name: name, number: pr_number.to_i)
    suites = response.dig(:repository, :pullRequest, :commits, :nodes, 0, :commit, :checkSuites, :nodes) || []
    parse_check_suites(suites)
  end

  def call_by_sha(repo_full_name, sha)
    owner, name = repo_full_name.split("/")
    response = run_graphql(:by_sha, owner: owner, name: name, sha: sha)
    suites = response.dig(:repository, :object, :checkSuites, :nodes) || []
    parse_check_suites(suites)
  end

  private

  def parse_check_suites(suites)
    suites.flat_map do |suite|
      app_name = suite.dig(:app, :name)
      (suite.dig(:checkRuns, :nodes) || []).map do |run|
        {
          app: app_name,
          name: run[:name],
          status: run[:status],
          conclusion: run[:conclusion],
          details_url: run[:detailsUrl],
          started_at: run[:startedAt],
          completed_at: run[:completedAt],
          annotations: (run.dig(:annotations, :nodes) || []).map do |a|
            {
              path: a[:path],
              start_line: a.dig(:location, :start, :line),
              end_line: a.dig(:location, :end, :line),
              level: a[:annotationLevel],
              message: a[:message],
              title: a[:title],
              raw_details: a[:rawDetails]
            }
          end
        }
      end
    end
  end
end
