# Draft for the team's Rails app. Cucumber step definitions are not included.
# Search returns papers using the existing fields in data/SCHEMA.md.
# These are synthetic records in an isolated test database.
# Fixture defaults: 2024 NeurIPS conference papers; empty cells mean NULL.
Feature: Search stored research papers
  Background:
    Given the following papers are stored:
      | title                          | abstract                        | keywords            | primary_topic      |
      | Graph neural networks          |                                 |                     |                    |
      | Learning representations       | A study of neural architectures |                     |                    |
      | Model compression              |                                 | neural; compression |                    |
      | Sequence prediction            |                                 |                     | Neural computation |
      | Reliable database transactions |                                 |                     |                    |
    And "Alice Researcher" from "Northbridge University" is an author of every paper
    And "Ben Researcher" from "Lakeside University" is also an author of "Graph neural networks"
    And I am viewing worldwide rankings for all areas from 2024 through 2024

  # Story 2: As a visitor, I want to search papers by keyword so that I can find research on my topic.
  @story_2
  Scenario Outline: Find matching papers regardless of capitalization
    When I search for "<keyword>"
    Then I should see exactly these papers in the search results, each once:
      | title                    |
      | Graph neural networks    |
      | Learning representations |
      | Model compression        |
      | Sequence prediction      |
    And I should not see "Reliable database transactions" in the search results

    Examples:
      | keyword |
      | neural  |
      | NEURAL  |

  # Story 3: As a visitor, I want to see each paper's authors and universities so that I know who does this research.
  @story_3
  Scenario: See who wrote a matching paper
    When I search for "networks"
    Then I should see exactly one result for "Graph neural networks"
    And that result should list these authors and their universities:
      | author           | university             |
      | Alice Researcher | Northbridge University |
      | Ben Researcher   | Lakeside University    |

  # Story 4: As a visitor, I want to know when nothing matches so that I can try another keyword.
  @story_4
  Scenario: Search for a keyword with no matches
    Given I have searched for "neural"
    When I search for "volcanology"
    Then I should see "No papers found"
    And I should see no paper results

  # Story 5: As a visitor, I want to clear my search so that I can return to the rankings.
  @story_5
  Scenario Outline: Clear a search
    Given I have searched for "<keyword>"
    When I press "Clear search"
    Then the "Search papers" field should be empty
    And I should see the same university rankings as before the search
    And my research area, year and location filters should be unchanged
    And I should see no paper results
    And I should not see "No papers found"

    Examples:
      | keyword     |
      | neural      |
      | volcanology |
