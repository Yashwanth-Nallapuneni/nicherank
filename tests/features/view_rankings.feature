# Draft for the team's Rails app. Cucumber step definitions are not included.
# See basic_rankings.feature for comparisons, filters, faculty and publications.
@story_1
Feature: View university rankings
  As a visitor
  I want to see university rankings
  So that I can compare universities.

  Scenario: View the rankings
    Given "Northbridge University" is the only university in the test database
    And its professor "Alice Researcher" has a stored 2024 NeurIPS paper titled "Graph neural networks"
    When I open NicheRank
    And I view worldwide rankings for all areas from 2024 through 2024
    Then I should see "Northbridge University" at rank 1
    And I should see a search field labelled "Search papers"
