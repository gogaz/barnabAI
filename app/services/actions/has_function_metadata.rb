# frozen_string_literal: true

module Actions
  module HasFunctionMetadata
    extend ActiveSupport::Concern

    class_methods do
      # Define or retrieve the function code
      # @param value [String, nil] The function code value (optional)
      # @yield Block that returns the function code (optional)
      # @return [String] The function code
      def function_code(value = nil, &block)
        if value || block
          @function_code = block || value
        else
          resolve_value(@function_code)
        end
      end

      # Define or retrieve the function description
      # @param value [String, nil] The function description value (optional)
      # @yield Block that returns the function description (optional)
      # @return [String] The function description
      def function_description(value = nil, &block)
        if value || block
          @function_description = block || value
        else
          resolve_value(@function_description)
        end
      end

      # Define or retrieve the function parameters (JSON schema format)
      # @param value [Hash, nil] The function parameters hash (optional)
      # @yield Block that returns the function parameters (optional)
      # @return [Hash] The function parameters
      def function_parameters(value = nil, &block)
        if value || block
          @function_parameters = block || value
        else
          resolve_value(@function_parameters) || {}
        end
      end

      def function_stops_reflexion?(value = nil, &block)
        if !value.nil? || block
          @function_stops_reflexion = block || value
        else
          resolve_value(@function_stops_reflexion) || false
        end
      end

      # Build a function declaration hash for Gemini API
      # @return [Hash] The function declaration
      def to_function_declaration
        {
          name: function_code,
          description: function_description,
          parameters: function_parameters
        }
      end


      private

      def resolve_value(stored)
        return nil unless stored

        stored.respond_to?(:call) ? instance_exec(&stored) : stored
      end
    end
  end
end
