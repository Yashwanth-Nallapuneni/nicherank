# Iteration 2: rank universities for a search topic (semantic ranking on Voyage embeddings + pgvector).
Feature: Rank universities by a research topic
  Background:
    Given the following universities and professors exist:
      | university             | professor        |
      | Northbridge University | Alice Researcher |
      | Southfield University  | Bob Builder      |
    And the following papers are stored with embeddings and authors:
      | title                               | professor        | concept |
      | Imitation learning from human video | Alice Researcher | 0       |
      | Query optimization for column stores | Bob Builder     | 2       |
      | Indexing for column stores          | Bob Builder      | 2       |
    And I am viewing worldwide rankings for all areas from 2024 through 2024

  # Story 14: As a student, I want universities ranked for my research topic, not only for
  # whole areas, so that I can find the strongest groups in my niche.
  @story_14
  Scenario: A meaning search ranks universities by their papers on that topic
    Given the embedding service places "teaching robots by showing them" at concept 0
    Then I should see "Southfield University" at rank 1
    When I search by "Meaning (semantic)" for "teaching robots by showing them"
    Then I should see "Rankings for “teaching robots by showing them”"
    And I should see "Northbridge University" at rank 1
    And I should not see "Southfield University" in the rankings

  @story_14
  Scenario: Faculty and their papers follow the topic
    Given "Bob Builder" also wrote "Robots that learn from video" at concept 0
    And the embedding service places "column store queries" at concept 2
    When I search by "Meaning (semantic)" for "column store queries"
    And I expand "Southfield University" and view Bob Builder's papers
    Then I should see "Papers on “column store queries”"
    And I should see "Query optimization for column stores"
    And I should see "Indexing for column stores"
    But I should not see "Robots that learn from video"

  @story_14
  Scenario: Keep the area ranking when the embedding service is down
    Given the embedding service is down
    When I search by "Meaning (semantic)" for "query optimization"
    Then I should see "Search by meaning is unavailable right now"
    And I should see "Southfield University" at rank 1
    And I should not see "Rankings for"
