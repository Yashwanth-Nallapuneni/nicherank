Feature: Sort institutions
  As a prospective graduate student
  I want to sort institutions by score or name
  So that I can compare research output and quickly find a university.

  Background:
    Given the following universities and professors exist:
      | university             | professor        |
      | Northbridge University | Alice Researcher |
      | Lakeside University    | Ben Researcher   |
      | Harbor University      | Cara Researcher  |
    And the following qualifying papers are stored:
      | title           | professor        | year | venue   |
      | Neural methods  | Alice Researcher | 2022 | NeurIPS |
      | Neural models   | Alice Researcher | 2024 | NeurIPS |
      | Learning        | Ben Researcher   | 2023 | NeurIPS |
      | Query planning  | Cara Researcher  | 2023 | SIGMOD  |
      | Query indexing  | Cara Researcher  | 2024 | SIGMOD  |
    And I am viewing worldwide rankings for all areas from 2022 through 2024

  Scenario Outline: Change display order without changing ranks or scores
    When I sort institutions by "<order>"
    Then the institutions should appear in this order: "<names>"
    And I should see "Northbridge University" at rank 1
    And I should see "Lakeside University" at rank 3
    And I should see "Harbor University" at rank 1
    And "Northbridge University" should have ranking score 2

    Examples:
      | order           | names                                                            |
      | Highest score   | Harbor University, Northbridge University, Lakeside University    |
      | Lowest score    | Lakeside University, Harbor University, Northbridge University    |
      | Institution A–Z | Harbor University, Lakeside University, Northbridge University    |

  Scenario: Keep sorting while filtering and exploring faculty papers
    When I sort institutions by "Institution A–Z"
    And I select only "Machine learning" and update the rankings
    Then the institutions should appear in this order: "Lakeside University, Northbridge University"
    When I expand "Northbridge University" and view Alice Researcher's papers
    And I return to the institution rankings
    Then institutions should still be sorted by "Institution A–Z"
    And the institutions should appear in this order: "Lakeside University, Northbridge University"
    And only "Machine learning" should remain selected
