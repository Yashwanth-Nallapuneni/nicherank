# CORE 2026 mapping audit — 2026-11-24

Issue [#12](https://github.com/Yashwanth-Nallapuneni/nicherank/issues/12) exposed missing ratings for NeurIPS and FOCS. Both are A* in the saved ICORE2026 source: [NeurIPS, entry 98](https://portal.core.edu.au/conf-ranks/98/) and [FOCS, entry 745](https://portal.core.edu.au/conf-ranks/745/).

The audit covered all 10,838 article/conference-paper venue groups in a fresh read-only database snapshot. These counts describe the proposed CSV and application changes; production data has not been updated.

| Measure | Before | After |
|---|---:|---:|
| CORE 2026 venue-name mappings | 282 | 397 |
| Conference-paper records with a visible CORE 2026 rating | 30,284 | 54,253 |
| Article records with a visible CORE 2026 conference rating | 0 | 722 |
| ERA 2010 mappings | 392 | 392 |
| SCImago 2025 mappings | 438 | 438 |

117 venue names gain a mapping, recovering ratings for 24,699 paper records. Two incorrect mappings covering eight records are removed, for a net increase of 24,691 rated records. The largest fixes include NeurIPS (3,220 records, including 413 articles), CVPR (2,652), CHI (2,300), AAAI (2,269), ICRA (2,145), ACL (1,501), NAACL-HLT (932), and FOCS (642).

## Matching policy

- Reuse the reviewed conference names in `venue_tiers.csv` only when the old entry ID still has the same title and acronym in ICORE2026. Always read the grade from ICORE2026; never carry a CORE2023 grade forward.
- Keep additional reviewed names and their source entry URLs in `icore2026_aliases.csv`. Exact normalized titles/acronyms and reviewed aliases are the only automatic matches. Word overlap and parenthesized acronyms generate review candidates, not grades.
- Independently ranked workshops can receive their own grade. Workshop, companion, Findings and other tracks cannot inherit a main conference's grade.
- Article/conference-paper metadata does not determine whether a recognized conference venue has a conference rating. Preprints and book chapters remain unrated. Journal ratings still require an article record.
- Preserve identified journal mappings when a bare name also resembles a conference. `Intelligent Data Analysis` and `Computer Supported Cooperative Work (CSCW)` remain in the review queue.
- Ungraded, national/regional, multiconference and journal-published source entries are not converted to A*/A/B/C. Unknown or ambiguous names stay unrated.

The two removed mappings were a combined CSE/EUC proceedings venue (previously assigned EUC's grade) and CAA SAFEPROCESS (previously assigned the separate IFAC event's grade). The [CAA event's own description](https://fdd2023.aconf.org/en-us/index.html) identifies its organizer and conference series. All 74 former acronym/word-overlap matches were reviewed; the other 72 are now explicit aliases. The refreshed queue contains 293 review rows, including one preserved journal review.

## Reproduce and apply

Create `venues.csv` with CSV headers using this read-only query against the intended database:

```sql
SELECT paper_type, venue, count(*) AS papers, count(venue_tier) AS tiered
FROM papers
WHERE paper_type IN ('conference-paper', 'article') AND venue IS NOT NULL
GROUP BY paper_type, venue
ORDER BY papers DESC, venue;
```

Regenerate only conferences so a missing ISSN cache cannot discard reviewed journal mappings:

```sh
bundle exec ruby data/script/data/map_venue_rankings.rb --conferences-only /path/to/venues.csv
bundle exec ruby data/script/data/build_venue_rankings.rb
```

The checked-in CSV can be loaded directly; regeneration is unnecessary for deployment. After merging, with `DATABASE_URL` set to the intended writable database, preview the transactional import, then apply it:

```sh
bundle exec ruby data/script/data/load_venue_rankings.rb
bundle exec ruby data/script/data/load_venue_rankings.rb --apply
```

Deploy the application change as well: otherwise conference ratings on article records remain hidden. The loader updates only `venue_rankings`. Its dry run rolls back, including table creation. A local import from the old CSV to the corrected CSV verified rollback, repeatability, and unchanged ERA/SCImago rows. No production write was performed for this PR.

## Earlier coverage report

The historical report below compares the original venue tiers with the first rating import; its counts use a different baseline from this audit.

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
