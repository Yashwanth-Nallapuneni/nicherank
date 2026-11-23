Feature: Find faculty by research topic
  As a student looking for a potential research advisor
  I want to find professors by the meaning of their research
  So that I can explore relevant people even when their papers use different wording

  Background:
    Given the following universities and professors exist:
      | university             | professor        |
      | Northbridge University | Alice Researcher |
      | Lakeside University    | Ben Researcher   |
      | Northbridge University | Cara Researcher  |
    And these faculty research profiles are available:
      | professor        | concept | publications |
      | Alice Researcher | 0       | 10           |
      | Ben Researcher   | 1       | 8            |
      | Cara Researcher  | 2       | 6            |
    And the embedding service places "learning from demonstrations" at concept 0

  Scenario: Find people by meaning, narrow to an institution and return from their publications
    When I open NicheRank
    And I open the faculty finder
    And I find faculty for "learning from demonstrations"
    Then "Alice Researcher" should be the first faculty match
    And I should see "Profile based on 10 publications"
    When I narrow faculty results to "Lakeside University"
    Then "Ben Researcher" should be the first faculty match
    And I should see 1 faculty match
    When I open the first faculty match and return
    Then the faculty search should keep "learning from demonstrations" at "Lakeside University"
    And I should see 1 faculty match

  Scenario: Keep the topic and institution while paging and clear the search
    Given faculty results show one profile per page
    When I open the faculty finder
    And I find faculty for "learning from demonstrations"
    And I narrow faculty results to "Northbridge University"
    And I open the next faculty page
    Then "Cara Researcher" should be the first faculty match
    And I should see "Page 2 of 2"
    When I open the first faculty match and return
    Then I should see "Page 2 of 2"
    And the faculty search should keep "learning from demonstrations" at "Northbridge University"
    When I clear the faculty search
    Then I should see "Enter a research topic"
    And the "Research topic" field should be empty

  Scenario: Explain an unavailable search and let the visitor retry
    Given the embedding service is down
    When I open the faculty finder
    And I find faculty for "learning from demonstrations"
    Then I should see "Faculty search is unavailable right now"
    And I should see 0 faculty matches
    Given the embedding service places "learning from demonstrations" at concept 0
    When I find faculty for "learning from demonstrations"
    Then "Alice Researcher" should be the first faculty match
