# frozen_string_literal: true

module Github
  module HasGraphqlQuery
    extend ActiveSupport::Concern

    class_methods do
      # Register a named GraphQL query. Call multiple times to register multiple queries.
      # Use run_graphql(name, variables) to execute.
      def graphql_query(name, query_string)
        graphql_queries[name] = query_string
      end

      def graphql_queries
        @graphql_queries ||= {}
      end
    end

    # Run a GraphQL query by name (symbol) or pass a raw query string directly.
    def run_graphql(query_or_name, variables = {})
      query_string = query_or_name.is_a?(Symbol) ? self.class.graphql_queries[query_or_name] : query_or_name
      raise ArgumentError, "Unknown query: #{query_or_name}" if query_string.blank?

      @client ||= Octokit::Client.new(access_token: @github_token)

      response = @client.post('/graphql', { query: query_string, variables: variables }.to_json)
      payload = response.to_h

      if payload[:errors]
        raise "GraphQLError: #{payload.dig(:errors).map { |e| e[:message] }.join(', ')}"
      end

      payload[:data]
    end
  end
end
