# venue_rankings coverage — 2026-11-19

Computed offline from a read-only snapshot of the live database (conference-paper and article papers that have a venue name). Preprints and book chapters are deliberately not graded. No database was modified.

| Paper type | Papers | Labeled before | Labeled after | Newly labeled | Coverage before → after |
|---|---:|---:|---:|---:|---|
| conference | 62794 | 34188 | 35643 | +1455 | 54.4% → 56.8% |
| journal | 44168 | 11765 | 20282 | +8517 | 26.6% → 45.9% |

"Before" = papers with `papers.venue_tier` (CORE2023 or team custom). "After" adds any venue that has a `venue_rankings` row.

## By source

| Source | Venues | Papers | Papers with no venue_tier today | Papers by ranking |
|---|---:|---:|---:|---|
| icore2026 | 255 | 19227 | 1455 | A: 4594, A*: 10877, B: 2893, C: 863 |
| era2010 | 307 | 8717 | 4413 | A: 2675, A*: 3807, B: 1676, C: 559 |
| scimago2025 | 391 | 13515 | 6137 | Q1: 13515 |

## Agreement with the existing CORE2023 venue_tier (ICORE2026 venues)

- same_grade: 194 venues
- venue_tier A -> ICORE2026 B: 6 venues
- venue_tier A -> ICORE2026 A*: 2 venues
- venue_tier B -> ICORE2026 C: 2 venues
- venue_tier B -> ICORE2026 A: 2 venues
- venue_tier A* -> ICORE2026 A: 1 venues

## Still unlabeled

7101 venues have papers with no label; the biggest are in `reports/venue_rankings/unmatched_venues.csv`. Typical reasons: LNCS/series names, absent venue names, workshop/companion/Findings tracks, conferences without a letter grade, journals not on ERA2010. 218 candidates are in `db/data/manual/venue_ranking_review.csv` for human review.

ISSN-based journal matching is incomplete: the free OpenAlex budget covered only part of the ISSN lookups, so journals whose names differ from the ERA2010 and SCImago titles may be added later. scimago2025 = SCImago 2025 journals with Q1 in a Computer Science category; a venue can have both a CORE grade and Q1.
