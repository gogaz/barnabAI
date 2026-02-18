# frozen_string_literal: true

class MCPAgent
  def initialize(user, functions)
    @functions = functions
    @ai_provider = AIProviderFactory.create(user)
  end

  def run(context)
    loop do
      prompt = context.build_structured_prompt(functions: @functions)
      response = @ai_provider.structured_output(prompt)
      puts '=' * 80
      puts response.inspect

      return response[:text] if response[:tools].blank?

      terminate = execute_tool_actions(context, response[:tools])
      return response[:text] if terminate

      context.add_assistant_message(response[:text]) if response[:text].present?
      puts context.inspect
    end
  end

  private

  def execute_tool_actions(context, tool_calls)
    tool_calls.any? do |call|
      klass = action_class_for(call[:name])
      fn = klass.new(context.user, context: context)

      begin
        result = fn.execute(call[:parameters])
      rescue StandardError => e
        context.add_function_call(call[:name], call[:arguments], e.message)
        puts e.message
        puts e.backtrace.join("\n")
        next
      end
      context.add_function_call(call[:name], call[:arguments], result)
      klass.function_stops_reflexion?
    end
  end

  def action_class_for(code)
    @functions.find { |klass| klass.function_code == code }
  end
end
