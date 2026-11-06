# NicheRank tests and implementation handoff

NicheRank's first version should support the basic CSRankings browsing flow plus keyword search over stored research papers. This folder contains the user stories and acceptance test drafts for that work. The application features, Rails test setup, and Cucumber step definitions still need implementation.

There are 11 stories and 18 example cases in each framework after expanding the parameterized examples. Cucumber describes the expected behavior; RSpec exercises the planned UI through Capybara. They cover the same behavior and need to stay consistent.

**Start here**

```text
tests/
  handoff.md
  features/
    view_rankings.feature
    basic_rankings.feature
    search_papers.feature
  spec/
    features/
      basic_rankings_spec.rb
      nicherank_spec.rb
    support/
      ranking_helpers.rb
```

Read the [basic ranking scenarios](features/basic_rankings.feature), [search scenarios](features/search_papers.feature), and [initial ranking scenario](features/view_rankings.feature). Their matching tests are [basic_rankings_spec.rb](spec/features/basic_rankings_spec.rb) and [nicherank_spec.rb](spec/features/nicherank_spec.rb). [ranking_helpers.rb](spec/support/ranking_helpers.rb) shares the filter setup.

**Stories to implement**

| Story | Visitor goal | Expected behavior |
| --- | --- | --- |
| 1 | Compare universities | Show universities in rank order with their scores and a paper-search field. |
| 2 | Find research by keyword | Match stored titles, abstracts, keywords, and topics regardless of capitalization; show each paper once. |
| 3 | Identify researchers | Each paper result shows its authors and their universities. |
| 4 | Understand an unsuccessful search | Show `No papers found` and remove previous paper results. |
| 5 | Return to the rankings | Clear the search, results, and empty-search message; restore the rankings and preserve the filters. |
| 6 | Compare research areas | Support one or multiple areas and update the eligible universities. |
| 7 | Compare a publication period | Apply inclusive start/end years and preserve the selected areas. |
| 8 | Compare locations | Filter by country or region and combine location with area/year filters. |
| 9 | Explore a university | Expand and collapse the faculty contributing to its selected ranking. |
| 10 | Learn about a professor | Link the professor's name to their stored website. |
| 11 | Inspect the underlying research | Show that professor's papers within the selected areas and years, including titles, years, and venues. |

**Use the existing data contract**

Read [data/SCHEMA.md](../data/SCHEMA.md), the [schema SQL](../data/db/postgres/schema.sql), and the [backend data handoff](../data/HANDOFF_FOR_YASHWANTH.md) before implementing models or queries. The data handoff documents an already-loaded application dataset; a new backend CSV importer is unnecessary.

The specs assume ActiveRecord models named `University`, `Professor`, `Paper`, and `Authorship`, using the existing numeric foreign keys. Professors belong to universities; authorships join professors to papers. Use `paper_type`, including `conference-paper`, and preserve nullable metadata. `keywords` is semicolon-separated text.

Keyword search can use the existing generated `papers.search_vector` with a parameterized `websearch_to_tsquery('english', query)`. Its inputs are title, keywords, primary topic, and abstract. Deduplicate paper IDs when joining authorships, while retaining all relevant author/university pairs in each result. Search returns papers; these stories do not introduce a keyword-based university scoring formula.

Tests need their own PostgreSQL database with the existing schema and cleanup between examples. The supplied schema enables the `vector` extension, so the test database must support it. The specs create synthetic records and should use a writable test connection. Application access and any changes to the shared schema remain coordinated with the data owner.

**Build in this order**

1. Wire the Rails models, database connection, and test environment. Keep the tests under this folder and connect Capybara to the app.
2. Implement the ranking query and page at `/`. Apply research areas, inclusive publication years, and location; show rank and numeric score. Add the faculty expansion and professor website links.
3. Implement the professor-paper view, retaining the selected areas and years. The fixture `Query planning` is an Alice paper in a different area; `Neural baselines` is outside the selected years. Both must be excluded in story 11.
4. Implement paper search, author/university display, the no-match state, and clearing the search while preserving ranking filters.
5. Add the institution location metadata and country-to-region mapping needed for story 8, adapting its fixture setup to the chosen storage.
6. Implement the Cucumber step definitions and run both full suites. Keep the feature scenarios and RSpec fixtures aligned as the UI is built.

The ranking implementation also needs an explicit venue-to-area mapping: the examples use NeurIPS for Machine learning and SIGMOD for Databases. The broad `papers.field` value and venue tiers do not establish that mapping by themselves.

Agree and document the ranking formula, tie handling, and publication eligibility rules. The tests establish relative order on synthetic publications; they do not prove exact CSRankings numerical parity. CSRankings adjusts credit using all coauthors and applies publication eligibility rules. The current authorships table represents roster faculty and does not provide every external coauthor or all eligibility metadata, so full parity needs additional data. See the [CSRankings methodology](https://csrankings.org/faq.html).

**Country/region dependency**

The user explicitly chose country/region filtering. The current `universities` schema has city and state but no country field. Story 8's fixture setup proposes `country_code` values `US`, `CA`, and `GB`; this is an integration placeholder, not an existing schema field or a migration instruction. Supply reliable location metadata and adapt that setup to the team's chosen storage.

The examples expect Canada to include Lakeside only, and North America to include Northbridge and Lakeside while excluding Harbor in the United Kingdom. Choosing Canada and Databases together produces `No universities match these filters` with no ranking rows. The RSpec location context raises a clear dependency error until its metadata setup is wired; its cases must be included in the completed suite.

**UI conventions used by the tests**

These are proposed labels and selectors. Adjust the tests and Cucumber steps together if the team chooses different wording or markup while preserving the behavior.

| UI element | Label or `data-testid` |
| --- | --- |
| Search controls | Field `Search papers`; buttons `Search` and `Clear search` |
| Ranking filters | `From year`, `To year`, `Country or region`; button `Update rankings` |
| Area controls | Container `research-area-filters`; `All areas` and individual area checkboxes |
| Rankings | Container `rankings`; rows `ranking-row`; cells `rank`, `university-name`, `ranking-score` |
| Faculty | Buttons `Show faculty` / `Hide faculty`; `faculty-list`, `faculty-row`, `faculty-name`; link `View papers` |
| Search results | `paper-results`, `paper-result`, `paper-title`, `paper-author` |
| Professor papers | Professor-name heading; `professor-papers`, `professor-paper`, `paper-title`, `paper-year`, `paper-venue` |

Each `paper-author` entry contains one author and their university. The ranking score must be readable as a number. A professor-paper view must preserve the active area/year selection. Empty ranking and search messages are distinct.

**Wire the runners without moving the folder**

Use the Rails app's Gemfile for `rspec-rails`, `capybara`, and `cucumber-rails` dependencies; `data/Gemfile` belongs to the data pipeline. Choose versions compatible with the team's Ruby/Rails versions. Configure a browser driver if controls use JavaScript. See [Capybara with RSpec](https://github.com/teamcapybara/capybara#using-capybara-with-rspec) and [Cucumber-Rails setup](https://cucumber.io/docs/installation/ruby/#ruby-on-rails).

The implementer should add these files under `tests`:

- `spec/spec_helper.rb` and `spec/rails_helper.rb`: initialize RSpec/Rails, load Capybara integration, configure the test database and cleanup. From `tests/spec`, the Rails environment path is `../../config/environment` relative to `__dir__`. The specs already load `spec/support/ranking_helpers.rb` explicitly.
- `features/support/env.rb`: initialize Cucumber-Rails/Capybara and scenario database cleanup.
- `features/step_definitions/*.rb`: create the described fixtures, drive the UI, and assert the visible results. Search-table empty cells mean SQL NULL; its papers default to 2024 NeurIPS conference papers. Use the same data and filter semantics as the RSpec examples.

After that wiring and the app implementation are in place, run from the Rails repository root:

```sh
RAILS_ENV=test bundle exec rspec -I tests/spec tests/spec/features
RAILS_ENV=test bundle exec cucumber --require tests/features tests/features
```

RSpec's `-I tests/spec` adds the custom helper directory to its load path so `require "rails_helper"` resolves there. The explicit Cucumber paths load support and step-definition files from this folder. Check existing runner configuration for assumptions about conventional root-level `spec/` or `features/` directories. The load-path flag is documented in the [RSpec CLI options](https://github.com/rspec/rspec-core/blob/main/lib/rspec/core/option_parser.rb).

**Remaining decisions and verification**

The scenarios do not yet specify blank queries, pagination, paper-result ordering, or whether paper search is narrowed by the ranking filters. Agree those behaviors and add scenarios when they enter scope. Clearing a search must preserve the ranking filters regardless.

Ruby syntax and static fixture-consistency checks have passed. The acceptance suites have not run against an application: this checkout currently has no Rails app, `rails_helper`, Cucumber support, or step definitions. Completion means all 18 RSpec examples and all 18 expanded Cucumber cases run against the implemented app, with the country/region cases included and no undefined steps. No application implementation or schema change is supplied by this test package.
