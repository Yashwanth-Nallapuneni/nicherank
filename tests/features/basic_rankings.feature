# Draft for the team's Rails app. Cucumber step definitions are not included.
# Extends story 1 and adds stories 6-11; search stories 2-5 remain separate.
# Country/region scenarios require extra institution location metadata.
# All publication fixtures have one author and represent qualifying research papers.
Feature: Browse and filter university rankings
  Background:
    Given the following universities and professors exist:
      | university             | professor        |
      | Northbridge University | Alice Researcher |
      | Northbridge University | Dana Researcher  |
      | Lakeside University    | Ben Researcher   |
      | Harbor University      | Cara Researcher  |
    And the following qualifying papers are stored:
      | title                    | professor        | year | venue   |
      | Neural baselines         | Alice Researcher | 2019 | NeurIPS |
      | Neural methods           | Alice Researcher | 2022 | NeurIPS |
      | Neural models            | Alice Researcher | 2024 | NeurIPS |
      | Reliable queries         | Dana Researcher  | 2024 | SIGMOD  |
      | Learning representations | Ben Researcher   | 2023 | NeurIPS |
      | Future learning          | Ben Researcher   | 2025 | NeurIPS |
      | Database indexing        | Cara Researcher  | 2023 | SIGMOD  |
      | Query planning           | Alice Researcher | 2024 | SIGMOD  |
    And NeurIPS belongs to "Machine learning" and SIGMOD belongs to "Databases"
    And I am viewing worldwide rankings for all areas from 2022 through 2024

  # Story 1: As a visitor, I want to see university rankings so that I can compare universities.
  @story_1
  Scenario: Compare universities in rank order
    When I select only "Machine learning" and update the rankings
    Then I should see "Northbridge University" at rank 1
    And I should see "Lakeside University" at rank 2
    And Northbridge should appear above Lakeside with a higher ranking score

  # Story 6: As a visitor, I want to choose research areas so that I can compare universities in subjects I care about.
  @story_6
  Scenario Outline: Filter by one research area
    When I select only "<area>" and update the rankings
    Then I should see only "Northbridge University" and "<other university>" in the rankings
    And I should not see "<excluded university>" in the rankings

    Examples:
      | area             | other university    | excluded university |
      | Machine learning | Lakeside University | Harbor University   |
      | Databases        | Harbor University   | Lakeside University |

  @story_6
  Scenario: Select more than one research area
    Given I am viewing rankings for only "Machine learning" from 2022 through 2024
    When I also select "Databases" and update the rankings
    Then I should see all three universities in the rankings
    And both research areas should remain selected

  # Story 7: As a visitor, I want to choose publication years so that I can compare research from a particular period.
  @story_7
  Scenario: Change the publication year range
    Given I am viewing rankings for only "Machine learning" from 2022 through 2024
    When I change the year range to 2023 through 2025 and update the rankings
    Then I should see "Lakeside University" at rank 1
    And I should see "Northbridge University" at rank 2
    And Lakeside should appear above Northbridge with a higher ranking score
    And only "Machine learning" should remain selected

  # Story 8: As a visitor, I want to choose a country or region so that I can compare universities where I want to study.
  @story_8 @requires_location_metadata
  Scenario: Filter by country
    Given the universities have the following country metadata:
      | university             | country        | country_code |
      | Northbridge University | United States  | US           |
      | Lakeside University    | Canada         | CA           |
      | Harbor University      | United Kingdom | GB           |
    And I reload the worldwide rankings for all areas from 2022 through 2024
    When I select "Canada" as the country or region and update the rankings
    Then I should see only "Lakeside University" in the rankings

  @story_8 @requires_location_metadata
  Scenario: Filter by region
    Given the universities have the following country metadata:
      | university             | country        | country_code |
      | Northbridge University | United States  | US           |
      | Lakeside University    | Canada         | CA           |
      | Harbor University      | United Kingdom | GB           |
    And I reload the worldwide rankings for all areas from 2022 through 2024
    When I select "North America" as the country or region and update the rankings
    Then I should see only "Northbridge University" and "Lakeside University" in the rankings
    And I should not see "Harbor University" in the rankings

  @story_8 @requires_location_metadata
  Scenario: Combine country and research area filters with no matches
    Given the universities have the following country metadata:
      | university             | country        | country_code |
      | Northbridge University | United States  | US           |
      | Lakeside University    | Canada         | CA           |
      | Harbor University      | United Kingdom | GB           |
    And I reload the worldwide rankings for only "Databases" from 2022 through 2024
    When I select "Canada" as the country or region and update the rankings
    Then I should see "No universities match these filters"
    And I should see no university ranking rows
    And the selected area should still be "Databases" with years 2022 through 2024

  # Story 9: As a visitor, I want to expand a university so that I can see the faculty contributing to its ranking.
  @story_9
  Scenario: Expand and collapse a university's faculty
    When I expand "Northbridge University"
    Then its faculty list should contain only "Alice Researcher" and "Dana Researcher"
    When I collapse "Northbridge University"
    Then its faculty list should be hidden
    And "Northbridge University" should still appear in the rankings

  # Story 10: As a visitor, I want a link to a professor's website so that I can learn about their work.
  @story_10
  Scenario: Find a professor's website link
    Given Alice Researcher's website is "https://example.org/alice"
    When I expand "Northbridge University"
    Then Alice Researcher's name should link to "https://example.org/alice"

  # Story 11: As a visitor, I want to view a professor's papers so that I can see the research behind the ranking.
  @story_11
  Scenario: View the papers contributing to a professor's ranking
    Given I am viewing rankings for only "Machine learning" from 2022 through 2024
    When I expand "Northbridge University" and view Alice Researcher's papers
    Then I should see exactly these papers with their years and venues:
      | title          | year | venue   |
      | Neural methods | 2022 | NeurIPS |
      | Neural models  | 2024 | NeurIPS |
    And I should not see "Neural baselines" or another professor's papers in that list
    And I should not see "Query planning" because it is outside the selected research area
