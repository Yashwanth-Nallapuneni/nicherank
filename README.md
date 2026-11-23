# NicheRank

- Joon Ahn (sa3883)
- Anthony Chang (ac5985)
- Sai Suhruth Reddy Karri (sk5843)
- Yashwanth Sai Nallapuneni (yn2509)

[Live app](https://nicherank-app-98c2ccb29d98.herokuapp.com/) | [GitHub repository](https://github.com/Yashwanth-Nallapuneni/nicherank)

## Requirements

Ruby 3.3.12 and Bundler 2.5.22. Tests also require a running local PostgreSQL 17 server with pgvector, a user allowed to create databases and extensions, and Google Chrome for the browser scenarios.

Run all commands from the repository root. Run `bundle install` once before starting the app or tests.

## Run

Place the privately supplied `nicherank-grader.env` in the repository root. It contains the connection to the populated database, the Voyage API key for semantic search, and a read-only connection setting. No Heroku account or login is needed.

```sh
set -a
. ./nicherank-grader.env
set +a
bin/rails server
```

Open http://localhost:3000. No database import or migration is needed. The environment file is excluded from Git and should be supplied separately through the private submission channel.

The Voyage API key enables Meaning/Hybrid paper search and Find faculty. Without it, Meaning/Hybrid fall back to keyword results and Find faculty shows an unavailable notice.

## Test

These commands use your Mac username with no password and PostgreSQL on port 5434. Adjust `TEST_DATABASE_URL` if your local database settings differ.

```sh
unset DATABASE_URL PGOPTIONS
export TEST_DATABASE_URL="postgres://$(whoami)@127.0.0.1:5434/nicherank_test"
RAILS_ENV=test bundle exec rspec
RAILS_ENV=test bundle exec cucumber
```

The test setup creates the local test database and required tables if needed, and uses synthetic records. Tests stub the embedding API, so they do not need Heroku access or a Voyage API key. `DATABASE_URL` and the read-only `PGOPTIONS` must be unset so tests can write to the local database.

[Cucumber user stories](tests/features) cover rankings and filters, paper search, sorting and pagination, saved institutions, venue ratings, and faculty search. [RSpec tests](tests/spec) cover the implementation. Country/region scenarios are currently excluded because the dataset does not provide country metadata.

