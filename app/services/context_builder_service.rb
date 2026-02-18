# frozen_string_literal: true

class ContextBuilderService
  # General guidelines that are always included in prompts
  GENERAL_GUIDELINES = [
    "You are a developers assistant that helps developers manage their work on Github.",
    "You have the skills of a senior developer with expertise in Github, pull requests, code reviews, and development workflows. Your goal is to assist developers in managing their pull requests, providing summaries, extracting information, and helping them stay organized.",
    "You are talking to senior developers about THEIR work, always assume they already have a minimal context on the topic, even if they say they don't, they do have at least minimal knowledge about the codebase in general, and good understanding of the languages and the frameworks.",
    "However they need reminders on what we're talking about : they have a lot to think about.",
    "Be very concise, friendly yet professional. Use 2nd person, nothing too formal. Don't abuse of meaningless emojis, but feel free to use them when appropriate to make the conversation more readable.",
    "Be direct: only greet the user if they greets you first. Your name is BarnabAI and your profile picture is a penguin in a tuxedo with Matrix glasses.",
    "Always respond in the user's language (match the language of their message).",
    "Always check for context in the messages to understand the user's intent and the context of the conversation.",
    "Format your messages using Slack mrkdwn syntax: use <URL|text> for hyperlinks, *bold* for bold, _italic_ for italics, ~strikethrough~ for strikethrough, and > for blockquotes. Use single backticks for inline code and triple backticks without language name for code blocks. For lists, use a hyphen - followed by a space.",
    "Always refer to users with their Slack User ID using the <@UABC123> format to ensure they get notified, instead of using their name.",
    "NEVER use the standard Markdown [text](URL) format. NEVER include the language code after the 3 backticks in code snippets. Escape the characters <, >, and & by replacing them with &lt;, &gt;, and &amp; respectively.",
    "Always prefer mrkdwn over plain text when you want to format your messages. If the message requires formatting (like links, bold, lists, etc.), use mrkdwn syntax. Only use plain text when the message is very simple and doesn't require any formatting.",
  ].freeze

  def initialize(user, channel_id: nil, thread_ts: nil, message_ts: nil)
    @user = user
    @channel_id = channel_id
    @thread_ts = thread_ts
    @message_ts = message_ts
    @conversation = []
  end

  attr_reader :conversation, :user

  def add_user_message(text, timestamp: nil)
    time = timestamp || Time.now
    add_message(role: "user", content: "#{time.utc.iso8601}:\n#{text}")
  end

  def add_assistant_message(text, timestamp: nil)
    time = timestamp || Time.now
    add_message(role: "assistant", content: "#{time.utc.iso8601}:\n#{text}")
  end

  def add_function_call(tool_name, arguments, response)
    add_function_call_message(tool_name, arguments)
    add_function_response_message(tool_name, response)
  end

  # Build prompt with system messages and conversation
  # @param additional_context [Array] Additional context strings to include in the prompt
  # @return [Array] Array of message hashes ready for AI provider
  def build_prompt(additional_context: [])
    system_messages(additional_context) + conversation
  end

  # Build structured prompt for Gemini function calling API
  # @param functions [Class, Array<Class>] Array of action classes that include HasFunctionMetadata
  # @param additional_context [Array] Additional context strings to include in the prompt
  # @return [Hash] Hash with :messages (Gemini contents format) and :functions (function declarations)
  def build_structured_prompt(functions: [], additional_context: [])
    all_messages = system_messages(additional_context) + conversation

    function_declarations = Array.wrap(functions).map do |fn_class|
      fn_class.to_function_declaration
    end

    {
      messages: all_messages,
      functions: function_declarations
    }
  end

  private

  def system_messages(additional_context)
    all_context = base_context + additional_context
    system_messages = [
      { role: "system", content: GENERAL_GUIDELINES.join("\n") },
    ]
    system_messages << { role: "system", content: all_context.join("\n") } if all_context.any?
    system_messages
  end

  def base_context
    context = []
    
    user_text = "Current user: #{@user.slack_username} (Slack ID: #{@user.slack_user_id}) - GitHub username: #{@user.primary_github_token&.github_username || 'not connected'}"
    context << user_text if user_text.present?

    context.compact
  end

  def add_message(**kwargs)
    role = kwargs[:role] || "user"
    @conversation << {
      **kwargs,
      role: role,
    }
    self
  end

  def add_function_call_message(tool_name, arguments)
    add_message(
      role: "function",
      action: "call",
      parts: [
        {
          functionCall: {
            name: tool_name,
            args: arguments
          }
        }
      ]
    )
  end

  def add_function_response_message(tool_name, content)
    add_message(
      role: "function",
      action: "response",
      parts: [
        {
          functionResponse: {
            name: tool_name,
            response: {
              content: content
            }
          }
        }
      ]
    )
  end
end
