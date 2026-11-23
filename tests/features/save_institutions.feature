@javascript
Feature: Save institutions
  As a prospective graduate student
  I want to bookmark institutions and revisit my saved list
  So that I can keep track of universities I am considering.

  Background:
    Given the following universities and professors exist:
      | university             | professor        |
      | Northbridge University | Alice Researcher |
      | Lakeside University    | Ben Researcher   |
    And the following qualifying papers are stored:
      | title          | professor        | year | venue   |
      | Neural methods | Alice Researcher | 2022 | NeurIPS |
      | Neural models  | Alice Researcher | 2024 | NeurIPS |
      | Query planning | Ben Researcher   | 2023 | SIGMOD  |
    And I am viewing worldwide rankings for all areas from 2022 through 2024

  Scenario: Save an institution and revisit it after a reload
    When I save "Northbridge University"
    Then the saved institution count should be 1
    When I open my saved institutions
    Then my visible saved institutions should be "Northbridge University"
    And I should see "Northbridge University" at rank 1
    When I reload the bookmarks page
    Then my visible saved institutions should be "Northbridge University"
    And "Northbridge University" should be marked as saved
    When I return to all institution rankings
    Then "Northbridge University" should be marked as saved
    And the saved institution count should be 1

  Scenario: Remove a saved institution without changing other bookmarks
    When I save "Northbridge University"
    And I save "Lakeside University"
    Then the saved institution count should be 2
    When I open my saved institutions
    And I unsave "Northbridge University"
    Then my visible saved institutions should be "Lakeside University"
    And the saved institution count should be 1
    When I unsave "Lakeside University"
    Then I should see "No saved institutions yet. Save an institution from Rankings."
    And my saved list should have no visible institutions
    And the saved institution count should be 0
    When I reload the bookmarks page
    Then my saved list should have no visible institutions

  Scenario: Explain an empty saved list
    When I open my saved institutions
    Then I should see "No saved institutions yet. Save an institution from Rankings."
    And my saved list should have no visible institutions

  Scenario: Filters hide bookmarks without deleting them
    When I save "Northbridge University"
    And I open my saved institutions
    And I select only "Databases" and update the rankings
    Then I should see "No saved institutions match these filters."
    And my saved list should have no visible institutions
    And the saved institution count should be 1
    When I select only "Machine learning" and update the rankings
    Then my visible saved institutions should be "Northbridge University"
    And "Northbridge University" should be marked as saved

  Scenario: Return to saved institutions after viewing faculty papers
    When I save "Northbridge University"
    And I open my saved institutions
    And I select only "Machine learning" and update the rankings
    And I expand "Northbridge University" and view Alice Researcher's papers
    And I return from papers to my saved institutions
    Then my visible saved institutions should be "Northbridge University"
    And only "Machine learning" should remain selected
    And "Northbridge University" should be marked as saved

  Scenario: Recover from damaged browser bookmark data
    Given the browser contains damaged bookmark data
    When I reload the bookmarks page
    And I save "Northbridge University"
    And I open my saved institutions
    Then my visible saved institutions should be "Northbridge University"
    And the saved institution count should be 1

  Scenario: Explain storage failures without pretending an institution was saved
    Given this browser refuses to store bookmarks
    When I save "Northbridge University"
    Then I should see "Browser storage is unavailable. Allow site storage to save institutions."
    And the saved institution count should be 0
    And "Northbridge University" should not be marked as saved

  Scenario: Reflect changes made in another browser tab
    When I save "Northbridge University"
    And I open my saved institutions
    And I remove the saved institution in another tab
    Then my saved list should have no visible institutions
    And the saved institution count should be 0
