# frozen_string_literal: true

module Github
  class QueryBuilder
    def initialize
      @where_conditions = []
      @not_conditions = []
      @any_of_groups = []
    end

    class << self
      def to_query(filters)
        builder = new
        filters.each { |key, value| builder.where("#{key}:#{value}") }
        builder.build
      end
    end

    # Add a WHERE condition (AND operator)
    # @param condition [String] The search condition (e.g., "is:pr", "author:gogaz")
    # @return [QueryBuilder] Returns self for method chaining
    def where(condition)
      @where_conditions << condition.to_s.strip
      self
    end

    # Add a NOT condition (negative search with minus)
    # @param condition [String] The condition to exclude (e.g., "archived:true")
    # @return [QueryBuilder] Returns self for method chaining
    def not(condition)
      @not_conditions << condition.to_s.strip
      self
    end

    # Add an ANY_OF group (OR operator)
    # @param *conditions [Array<String>] Multiple conditions that will be OR'd together
    # @return [QueryBuilder] Returns self for method chaining
    def any_of(*conditions)
      conditions = conditions.flatten.map(&:to_s).map(&:strip).reject(&:empty?)
      @any_of_groups << conditions unless conditions.empty?
      self
    end

    # Build the final query string
    # @return [String] The constructed GitHub search query
    def build
      parts = []

      # Add WHERE conditions (AND)
      parts.concat(@where_conditions) unless @where_conditions.empty?

      # Add NOT conditions (with minus prefix)
      parts.concat(@not_conditions.map { |condition| "-#{condition}" }) unless @not_conditions.empty?

      # Add ANY_OF groups (OR, wrapped in parentheses)
      @any_of_groups.each do |group|
        if group.length == 1
          parts << group.first
        else
          parts << "(#{group.join(' OR ')})"
        end
      end

      parts.join(" ")
    end

    # Alias for build
    def to_s
      build
    end
  end
end

# Global alias for convenience
GithubQueryBuilder = Github::QueryBuilder
