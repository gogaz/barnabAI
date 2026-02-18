# frozen_string_literal: true

require "set"

class CodeOwnersMatcher
  def initialize(github_service, repository)
    @github_service = github_service
    @repository = repository
  end

  # Determine impacted teams for a list of files
  def determine_impacted_teams(files, ref: nil)
    return [] if files.blank?

    codeowners_content = fetch_codeowners(ref: ref)
    return [] unless codeowners_content

    # Parse CODEOWNERS manually
    codeowners_rules = parse_codeowners(codeowners_content)

    # Match files against CODEOWNERS rules
    impacted_teams = Set.new
    files.each do |file|
      filename = file.filename || file[:filename] || file["filename"]
      next unless filename
      normalized_filename = filename.start_with?("/") ? filename : "/#{filename}"

      matching_teams = match_file_to_codeowners(normalized_filename, codeowners_rules)
      impacted_teams.merge(matching_teams) if matching_teams&.any?
    end

    impacted_teams.to_a
  rescue StandardError => e
    Rails.logger.error("Failed to determine impacted teams: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    []
  end

  private

  # Fetch CODEOWNERS file from repository
  def fetch_codeowners(ref: nil)
    codeowners_file = @github_service.get_file_content(
      @repository,
      "documentation/CODEOWNERS",
      ref: ref
    )

    return codeowners_file[:content] if codeowners_file&.dig(:content)

    # Try master branch if main doesn't work
    codeowners_file = @github_service.get_file_content(
      @repository,
      "documentation/CODEOWNERS",
      ref: "master"
    )

    codeowners_file&.dig(:content)
  rescue StandardError => e
    Rails.logger.warn("Failed to fetch CODEOWNERS file: #{e.message}")
    nil
  end

  # Parse CODEOWNERS file content
  # Returns an array of rules: [{ pattern: "...", teams: ["@team1", "@team2"] }]
  def parse_codeowners(content)
    return [] unless content

    rules = []
    content.each_line do |line|
      # Skip comments and empty lines
      line = line.strip
      next if line.empty? || line.start_with?("#")

      # Remove inline comments (everything after # that's not part of the pattern/owners)
      if line.include?("#") && !line.start_with?("#")
        comment_index = line.index(/\s+#/)
        line = line[0...comment_index] if comment_index
        line = line.strip
      end

      next if line.empty?

      # Split by whitespace: pattern followed by owners
      parts = line.split(/\s+/)
      next if parts.empty?

      pattern = parts[0]
      # Owners can be @team, @user, or email addresses
      owners = parts[1..-1].select { |part| part.include?("@") }

      rules << { pattern: pattern, teams: owners } unless owners.empty?
    end

    # Sort by pattern specificity (more specific patterns first)
    # GitHub CODEOWNERS matches patterns in order, with more specific patterns taking precedence
    rules.sort_by do |rule|
      pattern = rule[:pattern]
      specificity = 0
      
      # Fewer wildcards = more specific
      specificity -= pattern.scan(/\*\*/).count * 200 # ** is least specific
      specificity -= pattern.scan(/\*(?!\*)/).count * 100 # * is less specific
      specificity -= pattern.count("?") * 50
      
      # Deeper paths (more /) = more specific
      specificity += pattern.count("/") * 10
      
      # More literal characters = more specific
      literal_chars = pattern.gsub(/[*?]/, "").length
      specificity += literal_chars
      
      specificity
    end.reverse
  end

  # Match a file path against CODEOWNERS rules
  # Returns array of team names that match
  def match_file_to_codeowners(filepath, rules)
    matching_teams = Set.new

    rules.each do |rule|
      pattern = rule[:pattern]
      teams = rule[:teams]

      if matches_pattern?(filepath, pattern)
        matching_teams.merge(teams)
      end
    end

    matching_teams.to_a
  end

  # Check if a file path matches a CODEOWNERS pattern using File.fnmatch
  # Supports glob patterns: *, **, ?
  # CODEOWNERS patterns are relative to repo root
  # * matches any characters except /
  # ** matches any characters including / (recursive)
  # ? matches a single character except /
  # Patterns can start with / (absolute) or be relative
  def matches_pattern?(filepath, pattern)
    # Normalize pattern: remove leading / if present (CODEOWNERS uses absolute paths)
    normalized_pattern = pattern.start_with?("/") ? pattern[1..-1] : pattern
    # Normalize filepath: remove leading / if present
    normalized_filepath = filepath.start_with?("/") ? filepath[1..-1] : filepath

    # Use File.fnmatch for all patterns (it supports ** natively)
    # FNM_PATHNAME: * doesn't match /
    # FNM_DOTMATCH: match leading dots
    File.fnmatch?(normalized_pattern, normalized_filepath, File::FNM_PATHNAME | File::FNM_DOTMATCH)
  end
end
