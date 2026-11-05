# NicheRank data — iteration 1

Ruby data pipeline and PostgreSQL 17 delivery for the team's Rails backend. **Main and dev are already loaded; no backend CSV import is required.**

Read [the backend handoff](HANDOFF_FOR_YASHWANTH.md), [the frozen database schema](SCHEMA.md), and [QA / coverage limitations](QA.md).

Delivered: 10 schools, 1,116 faculty, 85,471 papers, 102,049 authorships, 97 verified aliases. Window: 2015-01-01 through 2026-11-04; no per-person cap. Thirteen roster identities remain unresolved; 25 unresolved CMU eligibility cases are omitted as agreed. Dataset completeness is explicitly false. Missing data and unresolved mappings remain NULL/review cases rather than guessed values.

## Repository layout

This package belongs under `data/` on the team's `data` branch. Commands below run from the package root (the repo's `data/` directory).

- `db/postgres/schema.sql`: agreed v2 schema; migration SQL is separate.
- `db/data/manual/`: source rosters, matches, aliases, tiers and review evidence.
- `db/data/sample/`: historical bounded Stanford sample, retained as a small fixture.
- `reports/`: credential-free QA and delivery manifests.
- `script/data/`: Ruby collectors, exporter, COPY loader, QA, dump and restore tools.
- `tmp/`: ignored local secrets, API caches and dump artifacts.
- `data/output/`: ignored bulk exports, delivered separately.

## Verification

Install Gemfile dependencies with Ruby 3.3, then:

```sh
ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |path| require_relative path }'
ruby script/data/collect.rb validate --output db/data/sample
```

Latest result: 28 tests, 92 assertions, no failures/errors. Both live branches passed full DB QA; the Postgres 17 archive passed a fresh restore test. Exact reports are in `reports/`.

## Resume collection

Set `OPENALEX_API_KEY` in ignored `.env.local` or the environment. The loader reads a private env file argument containing `DATABASE_URL`; credentials never belong in Git. Source/API caches are deliberately excluded from Git, so another computer needs the separately saved caches for offline replay.

```sh
ruby script/data/collect_author_metadata.rb db/data/manual/accepted_author_matches.csv
ruby script/data/collect_work_pages.rb db/data/manual/accepted_author_matches.csv
ruby script/data/export_full.rb
ruby script/data/load_postgres.rb data/output/full /private/path/connection.env
ruby script/data/qa_postgres.rb /private/path/connection.env data/output/full tmp/qa.json
```

Collection checkpoints are resumable; completed author batches are reused. New snapshots require a deliberate cutoff/cache refresh; the current full-collection scripts are pinned to this delivery's cutoff. Raw collection does not itself approve candidate identities. Accepted identity and alias decisions are separate auditable inputs. The older `collect.rb` entry point remains for the sample and small verified-roster workflow; it is not the bulk pipeline used for this delivery.

Current faculty affiliation groups historical papers. Deduplication conservatively folds DOI matches or safe title/year/author matches and retains provenance. Source career metrics come from canonical OpenAlex profiles. Custom journal tiers are project policy, not CORE journal ratings. See the detailed limitations in `QA.md`.

The user allowed CSRankings data; this release uses official faculty directories, OpenAlex and CORE2023. No substitute Rails app was created. Historical preparation-only notes in `docs/` are superseded by the current handoff.
