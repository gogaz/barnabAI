# frozen_string_literal: true

require "test_helper"

class ProcessGithubWebhookJobTest < ActiveJob::TestCase
  setup do
    @slack_installation = slack_installations(:one)
    @repository = repositories(:one)
  end

  test "should ignore non-pull_request events" do
    assert_no_enqueued_jobs only: UpdatePullRequestTeamsJob do
      ProcessGithubWebhookJob.perform_now(
        event_type: "push",
        delivery_id: "test-delivery",
        payload: {}
      )
    end
  end

  test "should ignore non-merged pull requests" do
    payload = {
      "action" => "closed",
      "pull_request" => {
        "number" => 123,
        "merged" => false
      },
      "repository" => {
        "id" => @repository.github_repo_id,
        "full_name" => @repository.full_name
      }
    }

    assert_no_enqueued_jobs only: UpdatePullRequestTeamsJob do
      ProcessGithubWebhookJob.perform_now(
        event_type: "pull_request",
        delivery_id: "test-delivery",
        payload: payload
      )
    end
  end

  test "should ignore pull requests for unknown repositories" do
    payload = {
      "action" => "closed",
      "pull_request" => {
        "number" => 123,
        "merged" => true
      },
      "repository" => {
        "id" => 999999,
        "full_name" => "unknown/repo"
      }
    }

    assert_no_enqueued_jobs only: UpdatePullRequestTeamsJob do
      ProcessGithubWebhookJob.perform_now(
        event_type: "pull_request",
        delivery_id: "test-delivery",
        payload: payload
      )
    end
  end

  test "should create pull request and enqueue UpdatePullRequestTeamsJob for merged PRs" do
    payload = {
      "action" => "closed",
      "pull_request" => {
        "id" => 12345,
        "number" => 999,
        "title" => "Test PR",
        "body" => "Test body",
        "state" => "closed",
        "merged" => true,
        "merged_at" => "2026-02-13T10:00:00Z",
        "created_at" => "2026-02-12T10:00:00Z",
        "updated_at" => "2026-02-13T10:00:00Z",
        "user" => { "login" => "testuser" },
        "base" => { "ref" => "main", "sha" => "abc123" },
        "head" => { "ref" => "feature", "sha" => "def456" }
      },
      "repository" => {
        "id" => @repository.github_repo_id,
        "full_name" => @repository.full_name
      }
    }

    assert_enqueued_with(job: UpdatePullRequestTeamsJob) do
      ProcessGithubWebhookJob.perform_now(
        event_type: "pull_request",
        delivery_id: "test-delivery",
        payload: payload
      )
    end

    pull_request = PullRequest.find_by(repository: @repository, number: 999)
    assert_not_nil pull_request
    assert_equal "Test PR", pull_request.title
    assert_equal "testuser", pull_request.author
    assert_equal "closed", pull_request.state
    assert_equal "main", pull_request.base_branch
    assert_equal "feature", pull_request.head_branch
  end

  test "should update existing pull request" do
    existing_pr = PullRequest.create!(
      repository: @repository,
      number: 888,
      github_pr_id: "old_id",
      title: "Old Title"
    )

    payload = {
      "action" => "closed",
      "pull_request" => {
        "id" => 88888,
        "number" => 888,
        "title" => "New Title",
        "body" => "Updated body",
        "state" => "closed",
        "merged" => true,
        "merged_at" => "2026-02-13T10:00:00Z",
        "created_at" => "2026-02-12T10:00:00Z",
        "updated_at" => "2026-02-13T10:00:00Z",
        "user" => { "login" => "testuser" },
        "base" => { "ref" => "main", "sha" => "abc123" },
        "head" => { "ref" => "feature", "sha" => "def456" }
      },
      "repository" => {
        "id" => @repository.github_repo_id,
        "full_name" => @repository.full_name
      }
    }

    assert_enqueued_with(job: UpdatePullRequestTeamsJob) do
      ProcessGithubWebhookJob.perform_now(
        event_type: "pull_request",
        delivery_id: "test-delivery",
        payload: payload
      )
    end

    existing_pr.reload
    assert_equal "New Title", existing_pr.title
    assert_equal "88888", existing_pr.github_pr_id
  end
end
