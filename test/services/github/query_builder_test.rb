# frozen_string_literal: true

require "test_helper"

class Github::QueryBuilderTest < ActiveSupport::TestCase
  def setup
    @builder = Github::QueryBuilder.new
  end

  test "builds simple query with where conditions" do
    query = @builder
      .where("is:pr")
      .where("is:open")
      .build

    assert_equal "is:pr is:open", query
  end

  test "builds query with where and not conditions" do
    query = @builder
      .where("is:pr")
      .where("author:gogaz")
      .not("archived:true")
      .build

    assert_equal "is:pr author:gogaz -archived:true", query
  end

  test "builds query with any_of conditions" do
    query = @builder
      .where("is:pr")
      .any_of("label:bug", "label:feature", "priority:high")
      .build

    assert_equal "is:pr (label:bug OR label:feature OR priority:high)", query
  end

  test "builds complex query with where, not, and any_of" do
    query = @builder
      .where("is:pr")
      .where("author:gogaz")
      .not("archived:true")
      .any_of("label:bug", "label:feature", "priority:high")
      .build

    expected = "is:pr author:gogaz -archived:true (label:bug OR label:feature OR priority:high)"
    assert_equal expected, query
  end

  test "builds query with multiple any_of groups" do
    query = @builder
      .where("is:pr")
      .any_of("label:bug", "label:critical")
      .any_of("assignee:alice", "assignee:bob")
      .build

    assert_equal "is:pr (label:bug OR label:critical) (assignee:alice OR assignee:bob)", query
  end

  test "builds query with only not conditions" do
    query = @builder
      .not("archived:true")
      .not("draft:true")
      .build

    assert_equal "-archived:true -draft:true", query
  end

  test "builds query with single condition in any_of" do
    query = @builder
      .where("is:pr")
      .any_of("label:bug")
      .build

    assert_equal "is:pr label:bug", query
  end

  test "handles empty any_of gracefully" do
    query = @builder
      .where("is:pr")
      .any_of
      .build

    assert_equal "is:pr", query
  end

  test "handles empty query builder" do
    query = @builder.build
    assert_equal "", query
  end

  test "handles string and symbol conditions" do
    query = @builder
      .where(:is_pr)
      .where("author:gogaz")
      .not(:archived)
      .build

    assert_equal "is_pr author:gogaz -archived", query
  end

  test "strips whitespace from conditions" do
    query = @builder
      .where("  is:pr  ")
      .where(" author:gogaz ")
      .build

    assert_equal "is:pr author:gogaz", query
  end

  test "handles array argument in any_of" do
    query = @builder
      .where("is:pr")
      .any_of(["label:bug", "label:feature"])
      .build

    assert_equal "is:pr (label:bug OR label:feature)", query
  end

  test "handles nested array in any_of" do
    query = @builder
      .where("is:pr")
      .any_of([["label:bug"], ["label:feature"]])
      .build

    assert_equal "is:pr (label:bug OR label:feature)", query
  end

  test "to_s alias works same as build" do
    @builder.where("is:pr").where("author:gogaz")
    assert_equal @builder.build, @builder.to_s
  end

  test "method chaining returns self" do
    result = @builder.where("is:pr")
    assert_same @builder, result

    result = @builder.not("archived:true")
    assert_same @builder, result

    result = @builder.any_of("label:bug")
    assert_same @builder, result
  end

  test "GithubQueryBuilder alias works" do
    builder = GithubQueryBuilder.new
    query = builder.where("is:pr").build
    assert_equal "is:pr", query
  end

  test "complex real-world example" do
    query = GithubQueryBuilder.new
      .where("is:pr")
      .where("is:open")
      .where("author:gogaz")
      .not("archived:true")
      .not("draft:true")
      .any_of("label:bug", "label:critical", "label:security")
      .any_of("repo:owner/repo1", "repo:owner/repo2")
      .build

    expected = "is:pr is:open author:gogaz -archived:true -draft:true (label:bug OR label:critical OR label:security) (repo:owner/repo1 OR repo:owner/repo2)"
    assert_equal expected, query
  end
end
