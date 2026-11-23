Feature: Explore publications by venue quality
  As a student comparing research
  I want to see and filter source-labeled venue ratings
  So that I can judge publication venues without treating different rating systems as equivalent

  Background:
    Given the following universities and professors exist:
      | university             | professor        |
      | Northbridge University | Alice Researcher |
    And the following qualifying papers are stored:
      | title              | year | venue   | professor        |
      | Learning at NeurIPS | 2024 | NeurIPS | Alice Researcher |
      | Learning at SIGMOD  | 2024 | SIGMOD  | Alice Researcher |
    And these venue ratings are available:
      | venue   | kind       | source    | ranking |
      | NeurIPS | conference | icore2026 | A*      |
    And I am viewing worldwide rankings for all areas from 2024 through 2024

  Scenario: Keep a rating selection while browsing faculty, paper sorting and Saved
    When I choose the venue rating "ICORE 2026 · A*"
    And I search for "learning"
    Then I should see exactly one result for "Learning at NeurIPS"
    And I should see "ICORE 2026 · A*"
    Given the embedding service is down
    When I search by "Meaning (semantic)" for "learning"
    Then I should see "Search by meaning is unavailable right now"
    And I should see exactly one result for "Learning at NeurIPS"
    When I sort the rated papers and browse their professor
    Then I should see "Venue rating: ICORE 2026 · A*"
    And I should see "Learning at NeurIPS"
    And I should not see "Learning at SIGMOD"
    When I follow "Back to rankings"
    Then the venue rating selection should be "ICORE 2026 · A*"
    When I open the saved version of these rated rankings
    Then the venue rating selection should be "ICORE 2026 · A*"

  Scenario: Distinguish journal sources and avoid duplicate search results
    Given a learning journal paper has ERA and SCImago ratings
    When I search for "learning"
    Then I should see "ERA 2010 · B"
    And I should see "SCImago 2025 · Q1"
    When I choose the venue rating "SCImago 2025 · Q1"
    Then I should see exactly one result for "Learning in a journal"

  Scenario: Show missing ratings, empty selections and reset without losing the query
    When I search for "learning"
    And I choose the venue rating "No listed rating"
    Then I should see exactly one result for "Learning at SIGMOD"
    And I should see "No listed rating"
    When I choose the venue rating "ICORE 2026 · C"
    Then I should see "No papers found"
    And I should see "No universities match these filters"
    When I follow "Reset"
    Then I should see "Learning at NeurIPS"
    And I should see "Learning at SIGMOD"
