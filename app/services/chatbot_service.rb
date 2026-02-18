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
        channel: channel_id,
        thread_ts: thread_ts,
        **build_github_oauth_invitation_message.to_h
      )
      return
    end

    # Build required context: user info, thread history, etc.
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

    context.add_function_call(
      "list_user_repositories",
      { user: @user.primary_github_token.github_username },
      Github::Client.new(@user).list_user_repositories
    )

    mappings = UserMapping.where(slack_user_id: required_mappings).to_h do |mapping|
      [mapping.slack_user_id, mapping.slice(:github_username, :slack_username)]
    end
    mappings[bot_user_id] = { slack_username: "BarnabAI (you)", github_username: nil }
    context.add_function_call(
      "list_all_known_slack_users",
      {},
      mappings
    )

    agent = ::MCPAgent.new(@user, [
      Actions::ApprovePRAction,
      Actions::ClosePRAction,
      Actions::MergePRAction,
      Actions::CreateCommentAction,
      Actions::RespondToCommentAction,
      Actions::RunWorkflowAction,
      Actions::GetPRDetailsAction
    ])
    message = agent.run(context)
    Slack::Client.send_message(
      channel: channel_id,
      thread_ts: thread_ts,
      text: message
    ) if message.present?

    # Detect and execute intent
    #structured_prompt = context.build_structured_prompt(functions: [
    #  Actions::SummarizeMyCurrentWorkAction,
    #  Actions::SinglePullRequestStatusUpdateAction,
    #  Actions::ListPrsByTeamsAction,
    #  Actions::UpdatePullRequestAction,
    #  #Actions::AskClarificationAction,
    #  #Actions::GeneralChatAction
    #])
    #structured_result = @ai_provider.structured_output(structured_prompt)
    #if structured_result[:tools].present?
    #  action_service = ActionExecutionService.new(@user, context: context)
    #  tool = structured_result[:tools].first
    #  response_messages = action_service.execute(tool[:name], tool[:parameters])
    #else
    #  response_messages = [Slack::MessageBuilder.new(text: structured_result[:text])]
    #end
#
    #response_messages.each do |message_builder|
    #  Slack::Client.send_message(
    #    channel: channel_id,
    #    thread_ts: thread_ts,
    #    **message_builder.to_h
    #  )
    #end
  end

  private

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
