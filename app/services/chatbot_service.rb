# frozen_string_literal: true

class ChatbotService
  def initialize(user)
    @user = user
    @ai_provider = AIProviderFactory.create(user)
  end

  def process_message(user_message, channel_id:, thread_ts:, message_ts:)
    # Check if user has GitHub token connected - required for all operations
    unless @user.has_github_token?
      Slack::Client.send_message(
        channel: @user.slack_user_id,
        **build_github_oauth_invitation_message.to_h
      )
      return
    end

    context = build_initial_context(user_message, channel_id:, thread_ts:, message_ts:)

    agent = ::MCPAgent.new(@user, [
      Actions::ApprovePRAction,
      Actions::ClosePRAction,
      Actions::MergePRAction,
      Actions::CreateCommentAction,
      Actions::RespondToCommentAction,
      Actions::RunWorkflowAction,
      Actions::GetPRDetailsAction,
      Actions::SearchPullRequestsAction,
      Actions::SummarizeMyCurrentWorkAction,
      Actions::ListUserRepositoriesAction,
    ])
    message = agent.run(context)
    # Reply in thread for channel messages, channel ids for direct messages start with 'D...'
    thread_ts = message_ts if channel_id.start_with?('D') && thread_ts.nil?

    Slack::Client.send_message(
      channel: channel_id,
      thread_ts: thread_ts,
      text: message
    ) if message.present?
  end

  private

  def build_initial_context(user_message, channel_id:, thread_ts:, message_ts:)
    # Initial context contains conversation history and github <> slack user mappings
    context = ContextBuilderService.new(
      @user,
      channel_id: channel_id,
      thread_ts: thread_ts,
      message_ts: message_ts,
    )

    required_mappings = [@user.slack_user_id]
    if thread_ts.present?
      thread_messages = Slack::Client.get_thread_messages(
        channel: channel_id,
        thread_ts: thread_ts
      )
      bot_user_id = ENV["SLACK_BOT_USER_ID"]
      thread_messages.each do |msg|
        role = msg[:user] == bot_user_id ? :assistant : :user
        text = Slack::MessageReader.read(msg[:text])
        required_mappings += Slack::Client.extract_mentioned_user_ids(text)
        context.add_user_message(text, timestamp: Time.at(msg[:ts].to_f)) if role == :user
        context.add_assistant_message(text, timestamp: Time.at(msg[:ts].to_f)) if role == :assistant
      end
    end
    context.add_user_message(user_message)

    mappings = UserMapping.where(slack_user_id: required_mappings).to_h do |mapping|
      [mapping.slack_user_id, mapping.slice(:github_username, :slack_username)]
    end
    mappings[bot_user_id] = { slack_username: "BarnabAI (you)", github_username: nil }
    context.add_function_call(
      "list_all_known_slack_users",
      {},
      mappings
    )
  end

  def build_github_oauth_invitation_message
    oauth_url = Rails.application.routes.url_helpers.github_oauth_authorize_url(
      slack_user_id: @user.slack_user_id,
      host: ENV.fetch("APP_HOST", "localhost:3000"),
      protocol: ENV.fetch("APP_PROTOCOL", "http")
    )

    user_tag = Slack::Messages::Formatting.user_link(@user.slack_user_id)

    blocks = [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "👋 Hi #{user_tag}! Nice to meet you, I'm BarnabAI :penguin::sunglasses:\nI need access to your GitHub account to help you :blush:"
        }
      },
      {
        type: "actions",
        elements: [
          {
            type: "button",
            text: {
              type: "plain_text",
              text: "Connect GitHub"
            },
            style: "primary",
            url: oauth_url
          }
        ]
      },
      {
        type: "context",
        elements: [
          {
            type: "mrkdwn",
            text: "💡 *Note:* If you're part of a GitHub organization, you may need to ask a repository owner to approve access to the organization."
          }
        ]
      }
    ]

    Slack::MessageBuilder.new(blocks: blocks)
  end
end
