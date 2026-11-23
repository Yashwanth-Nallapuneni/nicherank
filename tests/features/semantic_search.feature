# Iteration 2: search papers by meaning (Voyage embeddings + pgvector).
Feature: Search papers by meaning
  Background:
    Given the following universities and professors exist:
      | university             | professor        |
      | Northbridge University | Alice Researcher |
    And the following papers are stored with embeddings:
      | title                               | concept |
      | Imitation learning from human video | 0       |
      | Query optimization for column stores | 2      |
    And I am viewing worldwide rankings for all areas from 2024 through 2024

  # Story 13: As a student, I want to search by meaning so that papers that describe
  # my topic in different words still show up.
  @story_13
  Scenario: Meaning search finds a paper that shares no words with the query
    Given the embedding service places "teaching robots by showing them" at concept 0
    When I search by "Keyword" for "teaching robots by showing them"
    Then I should see "No papers found"
    When I search by "Meaning (semantic)" for "teaching robots by showing them"
    Then "Imitation learning from human video" should be the first search result

  @story_13
  Scenario: Hybrid search combines keyword and meaning matches
    Given the embedding service places "column store queries" at concept 2
    When I search by "Both (hybrid)" for "column store queries"
    Then "Query optimization for column stores" should be the first search result

  @story_13
  Scenario: Fall back to keyword search when the embedding service is down
    Given the embedding service is down
    When I search by "Meaning (semantic)" for "query optimization"
    Then I should see "Search by meaning is unavailable right now"
    And I should see exactly one result for "Query optimization for column stores"
