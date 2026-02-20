# frozen_string_literal: true

require "test_helper"

class GithubWebhooksControllerTest < ActionDispatch::IntegrationTest
  test "should enqueue job for valid webhook" do
    payload = {
      action: "closed",
      pull_request: {
        number: 123,
        merged: true
      },
      repository: {
        id: 456,
        full_name: "owner/repo"
      }
    }

    assert_enqueued_with(job: ProcessGithubWebhookJob) do
      post github_webhooks_url,
           params: payload.to_json,
           headers: {
             "Content-Type" => "application/json",
             "X-GitHub-Event" => "pull_request",
             "X-GitHub-Delivery" => "test-delivery-id"
           }
    end

    assert_response :ok
  end

  test "should return bad request for invalid JSON" do
    post github_webhooks_url,
         params: "invalid json",
         headers: {
           "Content-Type" => "application/json",
           "X-GitHub-Event" => "pull_request",
           "X-GitHub-Delivery" => "test-delivery-id"
         }

    assert_response :bad_request
  end
end
