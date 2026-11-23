# venue_rankings coverage — 2026-11-19

Computed offline from a read-only snapshot of the live database (conference-paper and article papers that have a venue name). Preprints and book chapters are deliberately not graded. No database was modified.

| Paper type | Papers | Labeled before | Labeled after | Newly labeled | Coverage before → after |
|---|---:|---:|---:|---:|---|
| conference | 95945 | 50159 | 52392 | +2233 | 52.3% → 54.6% |
| journal | 68932 | 16655 | 32406 | +15751 | 24.2% → 47.0% |

"Before" = papers with `papers.venue_tier` (CORE2023 or team custom). "After" adds any venue that has a `venue_rankings` row.

## By source

| Source | Venues | Papers | Papers with no venue_tier today | Papers by ranking |
|---|---:|---:|---:|---|
| icore2026 | 300 | 30365 | 2223 | A: 7361, A*: 15714, B: 5694, C: 1596 |
| era2010 | 394 | 15312 | 8773 | A: 5144, A*: 5753, B: 3312, C: 1103 |
| scimago2025 | 439 | 22198 | 11524 | Q1: 22198 |

## Agreement with the existing CORE2023 venue_tier (ICORE2026 venues)

- venue_tier  -> ICORE2026 B: 78 venues
- venue_tier  -> ICORE2026 C: 53 venues
- venue_tier  -> ICORE2026 A: 51 venues
- venue_tier  -> ICORE2026 A*: 38 venues

## Still unlabeled

9692 venues have papers with no label; the biggest are in `reports/venue_rankings/unmatched_venues.csv`. Typical reasons: LNCS/series names, absent venue names, workshop/companion/Findings tracks, conferences without a letter grade, journals not on ERA2010. 298 candidates are in `db/data/manual/venue_ranking_review.csv` for human review.

ISSN-based journal matching is incomplete: the free OpenAlex budget covered only part of the ISSN lookups, so journals whose names differ from the ERA2010 and SCImago titles may be added later. scimago2025 = SCImago 2025 journals with Q1 in a Computer Science category; a venue can have both a CORE grade and Q1.
