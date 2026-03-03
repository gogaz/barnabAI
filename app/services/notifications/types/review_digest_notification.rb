# frozen_string_literal: true

module Notifications
  module Types
    class ReviewDigestNotification < BaseNotification
      notification_type "review_digest"
      category "Code Review"
      description "AI summary of pull request reviews with full context"
      default_enabled true
      priority 5

      def self.match?(event_type, payload)
        event_type == "pull_request_review" &&
          payload.dig("action") == "submitted" &&
          payload.dig("review", "state") != "pending"
      end

      def self.recipients(event_type, payload)
        repo = payload.dig("repository", "full_name")
        pr_number = payload.dig("pull_request", "number")
        reviewer = payload.dig("review", "user", "login")

        pr = PullRequest.find_by(repository_full_name: repo, number: pr_number)
        return [] unless pr

        github_logins = [pr.author].compact
        github_logins.reject! { |login| login == reviewer }
        return [] if github_logins.empty?

        User.where(slack_user_id: UserMapping.where(github_username: github_logins).select(:slack_user_id))
      end

      def build_message(user)
        pr_details = Github::PullRequestFetcher.new(user).call(repo_full_name, pr_number)

        digest = ai_provider.chat_completion(
          build_review_digest_prompt(pr_details),
          response_format: :text
        )

        state_emoji = case review_state
        when "APPROVED", "approved" then ":white_check_mark:"
        when "CHANGES_REQUESTED", "changes_requested" then ":warning:"
        else ":speech_balloon:"
        end

        Slack::MessageBuilder.new(text: "New review on #{repo_full_name}##{pr_number}")
          .add_header_block("#{state_emoji} Review on ##{pr_number}")
          .add_section_block("*<https://github.com/#{repo_full_name}/pull/#{pr_number}|#{pr_details.dig(:meta, :title)}>*\n*Reviewer:* #{reviewer_login} · *Verdict:* #{review_state.humanize}")
          .add_divider
          .add_section_block(digest)
          .add_context_block("<https://github.com/#{repo_full_name}/pull/#{pr_number}|View pull request>")
      end

      private

      def repo_full_name = @payload.dig("repository", "full_name")
      def pr_number = @payload.dig("pull_request", "number")
      def reviewer_login = @payload.dig("review", "user", "login")
      def review_state = @payload.dig("review", "state")

      def build_review_digest_prompt(pr_details)
        [
          { role: "system", content: <<~PROMPT.strip },
            You summarize code reviews for the PR author. You receive the full review
            including inline comments with their diff context. Produce a concise,
            actionable summary in Slack mrkdwn format. Group feedback by theme.
            Highlight blocking issues vs suggestions. Do not repeat diff code verbatim.
            Do not use headers.
          PROMPT
          { role: "user", content: <<~CONTENT.strip }
            PR: #{pr_details[:meta][:title]} (#{repo_full_name}##{pr_number})
            Reviewer: #{reviewer_login} | Verdict: #{review_state}

            Review comments (with diff context):
            #{pr_details[:discussions][:code].to_json}

            Top-level reviews:
            #{pr_details[:discussions][:global].to_json}

            Current CI status:
            #{pr_details[:ci_checks].to_json}
          CONTENT
        ]
      end
    end
  end
end
