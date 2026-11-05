# NicheRank data handoff for Yashwanth

**The database is already loaded. No CSV import is needed from the backend.**

Main and dev contain 10 schools, 1,116 faculty, 85,471 deduplicated papers, 102,049 authorships and 97 verified alias links. Publication window: 2015-01-01 through 2026-11-04, no per-person cap. Both branches passed database QA. The PostgreSQL 17 dump passed a fresh restore test.

**Coverage caveat:** 13 faculty identities remain unresolved and are explicitly listed in `QA.md`; the 25 previously agreed unresolved CMU eligibility cases are omitted. This is the expanded ten-school available-profile dataset, not certified 100% faculty or bibliography coverage. Possible duplicate and venue cases remain documented rather than silently merged/ranked.

## What to use

1. Configure Rails `DATABASE_URL` from the privately shared **main read-only** connection file. Use the separate **dev read-only** file for dev queries. Neither connection string is in Git or this document.
2. Use `SCHEMA.md` as the frozen contract. `papers.paper_type` contains `conference-paper`; `papers.venue_tier_source` contains `core2023` / `custom` / NULL. Weighted generated full-text search is already installed: title A, keywords A, primary_topic B, abstract C.
3. Use normal ActiveRecord models and the existing numeric foreign keys. Count distinct paper IDs across authorship joins. Aliases are already folded into canonical professors.
4. Do not run a backend CSV import, recreate the tables, or use the reader role for migrations. Data-team scripts handle schema/loading/QA. Coordinate a concrete migration with Suhruth if backend changes require one.

## Delivered files

- `SCHEMA.md`: tables, fields, values, relationships and parameterized keyword search example.
- `QA.md`: school counts, QA results, provenance and known coverage gaps.
- `reports/`: machine-readable main/dev QA, read-only checks, dataset manifest, dump restore verification and free OpenAlex usage.
- `db/data/manual/`: roster, inclusion/exclusion decisions, accepted matches/aliases, CORE2023 mappings and unresolved identity list.
- `script/data/`: Ruby collection, export, transactional COPY loader, QA and PostgreSQL 17 dump/restore verification tools.
- Separate delivery archive: full export CSVs, manifests and `NicheRank_2026-11-04_pg17.dump`. Dumps and bulk export data are not committed.

The Git contribution belongs on branch **data**, entirely under **data/**. The repository data package has its own Gemfile; merge needed dependencies into the Rails app's Gemfile instead of replacing it. Collection is Ruby, not JavaScript.

## Private connection files on Suhruth's computer

These are ignored local files, to share through your private channel:

- Main reader: `nicherank-data/tmp/credentials/nicherank-main-readonly.env`
- Dev reader: `nicherank-data/tmp/credentials/nicherank-dev-readonly.env`

The old `nicherank_app` password was retained at Suhruth's request. Owner credentials are not included in the delivery archive. This document does not itself send credentials or messages to anyone.

## Questions / coordination status

No blocking schema, import-format or API-key questions remain for Yashwanth. Conference type, NULL handling, alias traceability, eligibility exclusions, custom venue provenance, cutoff and DB ownership follow the agreement. The deadline is ASAP, as requested by Suhruth. The remaining identity/venue/duplicate review items are data-quality follow-up, documented in `QA.md`, rather than backend import tasks.

Historical sample-only instructions in `docs/` are superseded by this handoff and `SCHEMA.md`.
