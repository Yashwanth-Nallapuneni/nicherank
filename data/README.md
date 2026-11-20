# NicheRank data — iteration 1

> **Iteration 2, continued (2026-11-20):** the dataset now covers 52 schools (3,446 professors, 223,694 papers) in the Heroku Postgres database `nicherank-db`, with CORE/Q1 venue labels in a new `venue_rankings` table. See [the section at the end](#iteration-2-continued--52-schools-and-venue-rankings--2026-11-20).

> **Iteration 2 (2026-11-15):** the dataset is extended to 25 schools — 2,157 professors, 149,932 papers, 184,759 authorships — and loaded into Neon **dev** only. `main` still holds the 10-school delivery described below. Same schema and cutoff. See [reports/iteration2/ITERATION2.md](reports/iteration2/ITERATION2.md) for method, QA and limitations.

Ruby data pipeline and PostgreSQL 17 delivery for the team's Rails backend. **Main and dev are already loaded; no backend CSV import is required.**

Read [the author/coverage/duplicate audit](reports/audit/AUDIT_REPORT.md), [the backend handoff](HANDOFF_FOR_YASHWANTH.md), [the frozen database schema](SCHEMA.md), and [QA / coverage limitations](QA.md).

Delivered: 10 schools, 1,126 faculty, 86,898 papers, 103,879 authorships, 101 verified aliases. Window: 2015-01-01 through 2026-11-04; no per-person cap. Three roster identities remain unresolved; 25 unresolved CMU eligibility cases are omitted as agreed. Dataset completeness is explicitly false. Missing data and unresolved mappings remain NULL/review cases rather than guessed values.

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

Latest result: 32 tests, 102 assertions, no failures/errors. Both live branches passed full DB QA; the Postgres 17 archive passed a fresh restore test. Exact reports are in `reports/`.

## Resume collection

Set `OPENALEX_API_KEY` in ignored `.env.local` or the environment. Python 3 standard-library audit scripts are optional data-team tools, not backend dependencies. The Ruby loader reads a private env file argument containing `DATABASE_URL`; credentials never belong in Git. Source/API caches are deliberately excluded from Git, so another computer needs the separately saved caches for offline replay.

```sh
ruby script/data/collect_author_metadata.rb db/data/manual/accepted_author_matches.csv
ruby script/data/collect_work_pages.rb db/data/manual/accepted_author_matches.csv
ruby script/data/export_full.rb
ruby script/data/load_postgres.rb data/output/full /private/path/connection.env
ruby script/data/qa_postgres.rb /private/path/connection.env data/output/full tmp/qa.json
```

Collection checkpoints are resumable; completed author batches are reused. New snapshots require a deliberate cutoff/cache refresh; the current full-collection scripts are pinned to this delivery's cutoff. Raw collection does not itself approve candidate identities. Accepted identity and alias decisions are separate auditable inputs. The older `collect.rb` entry point remains for the sample and small verified-roster workflow; it is not the bulk pipeline used for this delivery.

Current faculty affiliation groups historical papers. Deduplication conservatively folds DOI matches or safe title/year/author matches and retains provenance. Source career metrics come from canonical OpenAlex profiles. Custom journal tiers are project policy, not CORE journal ratings. See the detailed limitations in `QA.md`.

This release uses official faculty directories, OpenAlex and CORE2023. The audit additionally uses user-approved CSRankings homepage/ORCID hints and publisher-deposited Crossref records; conflicting hints are not automatically accepted. No substitute Rails app was created. Historical preparation-only notes in `docs/` are superseded by the current handoff.

Audit revision 2 corrected four canonical profiles, resolved ten missing identities, tightened alias evidence, curated high-risk mixed-profile attributions, and stopped generic-title / conflicting-formal-DOI merges. Use `--reconcile` only for an audited revision-2 data-owner update after backup and dev QA; the default loader remains an upsert. See the audit report for inconclusive samples and partial-bibliography limits.

## Venue/vector delivery update — 2026-11-05

See `DELIVERY.md` for the latest dump and rebuild command, and `reports/venues/TIER_COVERAGE.md` for the tier refresh. Both branches have pgvector 0.8.0. Required schema names remain unchanged. Live counts: 10 schools, 1,126 professors, 86,898 papers, 103,879 authorships, 101 aliases, 2,013 duplicate trace rows and 9,089 review-history rows (8,740 current export cases). Latest Ruby checks: 34 tests / 104 assertions passed. Fresh restore/rebuild QA files under `reports/venues/` supersede earlier delivery verification.

## Iteration 2 (continued) — 52 schools and venue rankings — 2026-11-20

Run-book with every command: [`reports/iteration2_continued/ITERATION2_CONTINUED.md`](reports/iteration2_continued/ITERATION2_CONTINUED.md).

**Where the data lives now.** One Heroku Postgres database (`nicherank-db`); Neon is no longer used. The Rails backend code was not changed.

| | Before | After (loaded 2026-11-20) |
|---|---:|---:|
| Schools | 25 | **52** |
| Professors | 2,157 | **3,446** |
| Papers | 149,932 | **223,694** |
| Authorships | 184,759 | **277,970** |
| Verified aliases | 119 | **141** |
| `venue_rankings` rows | 0 | **1,112** |

The window and cutoff are unchanged (2015-01-01 to 2026-11-04). All 2,157 existing professors are identical after the load. Of the 149,932 existing papers, 149,920 are byte-identical, 11 were merged as duplicates of a newly collected version (traceable in `paper_duplicates`) and one took the group's highest citation count (the existing dedup rule).

### What was done

1. **Schools.** CSRankings US top 49, all areas, 2015-2026 (four schools tie at 49th), minus the 25 already loaded: 27 new schools. Institution IDs are exact ROR matches (`universities.csv`, `institution_verification.csv`).
2. **Rosters.** `prepare_iteration2_continued.rb` parses the official department directories registered in `iteration2_continued_sources.json` and merges the new schools only; existing rows are never rewritten. Same scope rule as before (tenure-track and research faculty; teaching, clinical, emeritus, adjunct, visiting, courtesy and other-department faculty excluded). 1,346 eligible faculty; 7 without a listed title are held. Pages that scripts cannot fetch (JavaScript lists, HTTP 403, a Cloudflare challenge) were saved from a normal browser; ASU's JavaScript list was rendered with a headless browser. No CAPTCHA or access control was bypassed.
3. **Homepage links.** Where a directory gave no profile link, the person's homepage from CSRankings' public faculty list is used (`build_homepage_fallbacks.rb`, 40 people). 1,344 of 1,346 faculty have a link.
4. **Identity matching** (OpenAlex), same evidence standard as before and never guessed: the institutional scan and resolver matched 1,211; the name-search retry added 67; a third pass (`iteration2_continued_orcid_pass.rb`) looks up the ORCID that CSRankings lists for a person and added 18 (a wrong ORCID is rejected, e.g. one that pointed to another person). **1,289 of 1,346 are accepted**; 22 split OpenAlex profiles were folded in as aliases. 64 cases stay in `iteration2_continued_review.csv` (57 identities, 7 eligibility).
5. **Papers and load.** Papers for the accepted profiles were collected with the existing scripts, deduplicated by the existing rules and exported with `export_full.rb`. Two checks gate the load: `check_export_quality.rb` (required schema fields on every row, and the new schools' fields — abstract, keywords, topic, venue, DOI, language, open access — must be about as complete as the existing schools') and `check_db_quality.rb` (per-school coverage after the load). The load itself is `load_postgres.rb --reconcile --prune-withdrawn`, rehearsed on a local restore of the production backup first.
6. **Venue quality labels.** New table `venue_rankings` (joined to papers on the exact venue name): ICORE2026 conference grades, ERA2010 CORE journal grades and SCImago 2025 Computer Science Q1 journals (`prepare_venue_rankings.rb`, `prepare_scimago_q1.rb`, `map_venue_rankings.rb`, `build_venue_rankings.rb`, `load_venue_rankings.rb`; coverage in `reports/venue_rankings/COVERAGE.md`). `papers.venue_tier` is unchanged. The table is data only: the app does not read it yet.

### Effect on the existing 25 schools

The ranking code is unchanged. A paper's point is split among the roster faculty who wrote it, so 3,011 papers shared with the new schools now split credit: existing schools' scores fall by 4.9% on average (2.6% to 8.4%), with one rank swap among them. Recomputing the old scores without the new professors reproduces the previous numbers (the residual is 0.3%).

### Open items

- **15 likely-eligible faculty to verify and add.** CSRankings lists them at these schools and OpenAlex shows them affiliated in 2025-2026, but they are absent from the directory pages we parsed and their homepages show a professor title with no emeritus/adjunct/courtesy wording. Confirm tenure-track or research appointment on the department page, then add them (and run identity matching and paper collection for them; it is incremental and cheap):
  George Mason: Alexander Brodsky, Massimiliano Albanese · Northwestern: Ermin Wei, Kenneth D. Forbus · Buffalo: David S. Doermann, Jinhui Xu, Shambhu Upadhyaya, Xin He · UC Riverside: Eamonn J. Keogh, Michalis Faloutsos, Vagelis Hristidis · Minnesota: Hyun Soo Park · Utah: Ponnuswamy Sadayappan · Virginia Tech: D. Scott McCrickard · Yale: Amin Karbasi.
  Ermin Wei appears to be an industrial-engineering faculty member, so check that appointment first.
- 25 more people in `reports/iteration2_continued/roster_gap_candidates.csv` are marked "verify manually" (unreachable homepage, emeritus wording, or not computing topics). They are not added.
- 64 held review cases in `iteration2_continued_review.csv`.
- ISSN lookups for journal venues are partial (1,325 venues looked up); the rest need a new OpenAlex budget (the free key allows $1/day) and will add a few more `venue_rankings` rows.
- Two UC Riverside faculty have no homepage link (the app shows the name as text).
