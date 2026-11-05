# NicheRank database contract — iteration 1

PostgreSQL 17; Ruby/Rails backend. Schema version 2 is frozen per the backend agreement. The data team owns schema creation, loading and QA; the backend does **not** need to import CSVs. Schema creation SQL is `db/postgres/schema.sql`; existing v1 databases use the already-applied `migrate_v2.sql`. No Rails migration version is fabricated or stamped by this pipeline.

## Tables and relationships

All entity/relationship `id` columns are bigint identity primary keys. Entity OpenAlex identifiers remain unique text natural keys. Foreign keys reference numeric IDs.

| Table | Key fields | Relationships / meaning |
|---|---|---|
| `universities` | `id`, unique `openalex_id` (`I…`), `name`, `short_name`, `city`, `state`, `cs_dept_url` | Ten selected institutions |
| `professors` | `id`, unique `openalex_id` (`A…`), `name`, `title`, `homepage_url`, `orcid`, `first_pub_year`, `works_count`, `h_index`, `match_confidence` | `university_id → universities.id`; current roster affiliation |
| `papers` | `id`, unique `openalex_id` (`W…`), `title`, `abstract`, `year`, `paper_type`, `venue`, `venue_tier`, `venue_tier_source`, `citations`, `doi`, `primary_topic`, `field`, `keywords`, `is_open_access`, `oa_url`, `language`, generated `search_vector` | One retained publication per conservative deduplication group |
| `authorships` | `id`, `professor_id`, `paper_id`, `position`, `is_corresponding` | Both foreign keys enforced; unique `(professor_id, paper_id)` |
| `author_aliases` | `id`, `professor_id`, unique `alias_openalex_id` | Verified alternate OpenAlex profile → canonical professor |
| `paper_duplicates` | primary key `discarded_openalex_id`, `retained_paper_id`, `reason` | Trace discarded publication IDs back to retained papers |
| `data_review_cases` | `id`, unique `fingerprint`, `issue_type`, `university`, `name_or_venue`, `candidate_ids`, `reason`, `status`, `resolution` | Identity, eligibility, venue and duplicate review trail |
| `dataset_metadata` | primary key `dataset_key`, `manifest` JSONB, `loaded_at` | Scope, cutoff, counts, hashes and limitations; older sample entries remain historical |

Universities, professors, papers, authorships and author_aliases have `created_at` / `updated_at` timestamps. The schema SQL is authoritative for exact types and constraints.

## Frozen paper names and values

- Use `papers.paper_type`, never `papers.type`. Values: `article`, `conference-paper`, `preprint`, `book-chapter`.
- `venue_tier`: `A*`, `A`, `B`, `C`, or SQL NULL.
- `venue_tier_source`: `core2023`, `custom`, or SQL NULL. Custom journal tiers are project policy, not CORE journal ratings. An unranked venue has both tier fields NULL.
- `position`: `first`, `middle`, `last`, or NULL.
- Unknown optional values are SQL NULL. Missing abstracts are not invented. Boolean `false` remains false.
- `keywords` is semicolon-separated text, not a JSON array. `doi` is a normalized lowercase DOI without its URL prefix.
- `match_confidence`: `high`, `medium`, `manual`. Automated name/institution matches are documented as automated, not individually human-verified.

The internal export CSV still uses legacy `type=proceedings-article`. The Ruby loader translates this at the database boundary. Backend code uses only the frozen PostgreSQL contract above.

## Keyword search

`search_vector` is a stored, generated English `tsvector` with a GIN index:

| Input | Weight |
|---|---|
| title | A |
| keywords | A |
| primary_topic | B |
| abstract | C |

```sql
SELECT id, title, year,
       ts_rank_cd(search_vector, websearch_to_tsquery('english', $1)) AS relevance
FROM papers
WHERE search_vector @@ websearch_to_tsquery('english', $1)
ORDER BY relevance DESC, citations DESC NULLS LAST, id
LIMIT $2 OFFSET $3;
```

Bind all parameters. Rails can use `websearch_to_tsquery` through a parameterized query; no external search service or JavaScript data service is needed. The generated vector updates automatically when its input columns change. The supplied query ranks papers; the backend's professor/school ranking formula remains backend-owned.

## Counting and interpretation

Count distinct paper IDs when joining authorships. A coauthored paper may count for several professors or schools, so school paper counts do not sum to the global unique-paper count. Aliases fold into the canonical professor before export and never create a second professor.

Publication window: 2015-01-01 through the recorded snapshot cutoff, inclusive. No per-person publication cap. Retracted records and types outside the four agreed types are excluded. Affiliation is the current faculty roster affiliation, not necessarily affiliation when a paper was written. Canonical OpenAlex career `works_count` and `h_index` are source metrics; they are not recomputed by summing aliases. Earliest publication year considers verified aliases and all source publication years.

Matched eligible professors with zero qualifying papers remain in the database and receive a review entry. Unresolved identities have no guessed professor ID; see the coverage exceptions in `QA.md` and `db/data/manual/identity_review_remaining.csv`.

## Access and operations

Private connection files are delivered separately. `nicherank_reader` is the intended backend read-only role on main and dev. `nicherank_app` is the earlier read/write application role; its existing password was retained at Suhruth's request. No credential belongs in Git or this document.

Run the loader from the data package root using an ignored private env file containing `DATABASE_URL=…`:

```sh
ruby script/data/load_postgres.rb data/output/full /private/path/connection.env
ruby script/data/qa_postgres.rb /private/path/connection.env data/output/full tmp/qa.json
ruby script/data/dump_postgres.rb /private/path/connection.env tmp/delivery/nicherank.dump
```

The loader validates input, COPY-loads temporary staging tables and upserts within one transaction. The default mode preserves existing data. Audited revision-2 updates can explicitly use `--reconcile` after backup and dev testing: it retains numeric professor IDs, applies documented canonical-ID corrections, removes superseded derived links/papers, and preserves old review cases as superseded history. Unchanged entity/link rows are not rewritten. Schema SQL is applied separately by the data owner. PostgreSQL 17 custom-format archives are restored with PostgreSQL 17 `pg_restore`; archives omit role definitions, ownership and grants.

## Audit revision 2

See `reports/audit/AUDIT_REPORT.md`. Eleven high-risk mixed profiles have independently supported publication curation; uncertain person-level `first_pub_year`, `works_count` and `h_index` remain NULL. Paper-level corrections are recorded in `paper_identity_overrides.csv`; a mixed source ID is not made a whole-person alias merely because selected papers are supported. Distinct formal publication DOIs remain separate without version evidence; generic titles require DOI evidence to merge. Three eligible roster identities remain unresolved.

Numeric IDs are local to a database branch; use OpenAlex natural keys to compare main/dev exports. The audited delivery dump is taken from **main**, preserving its numeric IDs on restore.

## Venue/vector delivery update — 2026-11-05

See `DELIVERY.md` for the latest dump and rebuild command, and `reports/venues/TIER_COVERAGE.md` for the tier refresh. Both branches have pgvector 0.8.0. Required schema names remain unchanged. Live counts: 10 schools, 1,126 professors, 86,898 papers, 103,879 authorships, 101 aliases, 2,013 duplicate trace rows and 9,089 review-history rows (8,740 current export cases). Latest Ruby checks: 34 tests / 104 assertions passed. Fresh restore/rebuild QA files under `reports/venues/` supersede earlier delivery verification.
