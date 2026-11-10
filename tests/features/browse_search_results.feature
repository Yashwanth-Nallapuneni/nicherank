Feature: Browse paper search results
  As a visitor
  I want to page through and sort matching papers
  So that I can explore more research and compare publication years.

  Background:
    Given the following universities and professors exist:
      | university             | professor        |
      | Northbridge University | Alice Researcher |

  # Story 12: Browse papers beyond the first page of search results.
  @story_12
  Scenario: Move to the next results page and return
    Given 51 numbered "Robotics study" papers are stored for "Alice Researcher"
    And I am viewing worldwide rankings for all areas from 2024 through 2024
    When I search for "robotics"
    Then I should see "Robotics study" papers numbered 1 through 50 in order
    When I go to the "Next" page of search results
    Then I should see "Robotics study" papers numbered 51 through 51 in order
    And my research area, year and location filters should be unchanged
    When I go to the "Previous" page of search results
    Then I should see "Robotics study" papers numbered 1 through 50 in order

  # Story 13: Sort matching papers to find newer or older research.
  @story_13
  Scenario: Change the publication-year sort order
    Given the following qualifying papers are stored:
      | title                | professor        | year | venue   |
      | Robotics methods     | Alice Researcher | 2023 | NeurIPS |
      | Robotics foundations | Alice Researcher | 2021 | NeurIPS |
      | Robotics advances    | Alice Researcher | 2024 | NeurIPS |
    And I am viewing worldwide rankings for all areas from 2021 through 2024
    When I search for "robotics"
    And I sort the search results by "Year (newest first)"
    Then I should see these search results in order:
      | title                |
      | Robotics advances    |
      | Robotics methods     |
      | Robotics foundations |
    When I sort the search results by "Year (oldest first)"
    Then I should see these search results in order:
      | title                |
      | Robotics foundations |
      | Robotics methods     |
      | Robotics advances    |
