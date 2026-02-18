# frozen_string_literal: true

module Github
  module HasGraphqlQuery
    extend ActiveSupport::Concern

    class_methods do
      def graphql_query(query_string)
        define_method(:fetch_raw_data) do |variables = {}|
          execute_graphql(query_string, variables)
        end
      end
    end

    private

    def execute_graphql(query, variables)
      @client ||= Octokit::Client.new(access_token: @github_token)

      response = @client.post('/graphql', { query: query, variables: variables }.to_json)

      payload = response.to_h

      if payload[:errors]
        raise "GraphQLError: #{payload.dig(:errors).map { |e| e[:message] }.join(', ')}"
      end

      payload[:data]
    end
  end
end