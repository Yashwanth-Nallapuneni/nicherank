# NicheRank frontend handoff

The Iteration 1 backend is on `main`: university rankings with research-area and year filters, faculty expansion, professor paper lists and keyword paper search, running on Suhruth's database. The pages work but are unstyled. This handoff covers the frontend work: layout, styling and accessibility, without changing behaviour.

**Start here**

1. Accept the GitHub invite to `Yashwanth-Nallapuneni/nicherank` while signed in as `joon0110` (the repo shows 404 until then).
2. Clone the repo and create a branch from `main`, e.g. `frontend`.
3. Open a pull request into `main` when done. Both test suites must pass.

Live app for reference: https://nicherank-app-98c2ccb29d98.herokuapp.com

**Files you own**

```text
app/views/rankings/index.html.erb      rankings, filters and paper search (route /)
app/views/professors/show.html.erb     a professor's papers (route /professors/:id)
app/views/layouts/application.html.erb page shell
app/assets/stylesheets/application.css all styles
```

The course requires ERB views and CSS. No frontend frameworks (React, Vue, etc.). Check with Yashwanth before adding any JavaScript: the acceptance tests use a driver without JavaScript, so anything JS-only would break them.

**What the tests depend on (do not change)**

The RSpec and Cucumber acceptance tests find elements by label and `data-testid`. Keep every `data-testid` attribute and these exact texts:

| Element | Label / text |
| --- | --- |
| Search | field `Search papers`; buttons `Search`, `Clear search` |
| Filters | selects `From year`, `To year`, `Country or region`; button `Update rankings` |
| Areas | checkbox `All areas (CSRankings venues)` and one checkbox per area |
| Faculty | buttons `Show faculty`, `Hide faculty`; link `View papers` |
| Messages | `No papers found`, `No universities match these filters` |

Also:
- The ranking score stays a plain number (e.g. `218.15`), with no units or extra text inside `ranking-score`.
- The professor page keeps an `h1` containing only the professor's name.
- Each `paper-author` element holds one author and their university.
- Forms keep their field names (`q`, `areas[]`, `all_areas`, `was_all`, `from`, `to`, `location`, `expand`). These carry the filter state between pages.

Moving elements, wrapping them in new containers, adding classes and restyling are all fine.

**Requested work**

1. Layout: on wide screens, put the rankings and the paper results side by side (rankings left, papers right). Today a long faculty list (e.g. Georgia Tech) pushes search results far down the page. Stack them on narrow screens.
2. Visual design: readable ranking rows, a clear filter panel (there are 25 area checkboxes), and paper results showing title, venue, year and authors.
3. Accessibility:
   - `<html lang="en">`
   - a `<legend>` for the search and the filter fieldsets
   - an `aria-label` on each `Show faculty` / `Hide faculty` button and `View papers` link that names the university or professor (the visible text must stay the same)
   - a page `<title>` per page (the professor's name on the professor page)
   - visible focus styles and enough colour contrast
4. Style the "Showing the top 50 of N matching papers" line above search results.

**Run it locally**

Requires Ruby 3.3, Bundler and Docker.

```sh
bundle install
export DATABASE_URL='<main read-only URL from nicherank-main-readonly.env>'   # never commit it
bin/rails server    # http://localhost:3000
```

The database is read-only, so the app only reads data.

**Run the tests**

Start the local test database once:

```sh
docker run -d --name nicherank-test-db -e POSTGRES_PASSWORD=postgres -p 5434:5432 pgvector/pgvector:pg17
```

Then run both suites before every push (the test database schema loads automatically):

```sh
bundle exec rspec
RAILS_ENV=test bundle exec cucumber
```

Expected: `41 examples, 0 failures` and `15 scenarios (15 passed)`. If a test fails after a markup change, a label or `data-testid` probably changed: restore it rather than editing the test. If you think a label should change, agree it with Anthony and Yashwanth first, then update the tests in the same pull request.

**Done means**

- The pull request into `main` has the layout, styling and accessibility changes.
- Both suites pass.
- The pages are checked in a browser at desktop and phone widths.
