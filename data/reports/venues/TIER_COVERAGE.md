# Venue coverage refresh — 2026-11-05

Snapshot cutoff remains 2026-11-04. No new OpenAlex collection or paid calls were required. All existing paper IDs and authorships were preserved.

| Paper type | Papers | Ranked before | Ranked after | Coverage after |
|---|---:|---:|---:|---:|
| conference-paper | 36,785 | 13,915 | 19,705 | 53.57% |
| article | 27,172 | 1,613 | 7,228 | 26.6% |
| preprint | 20,436 | 0 | 0 | 0.0% |
| book-chapter | 2,505 | 0 | 0 | 0.0% |

11,405 papers received a tier. Total NULL tiers fell from 71,370 to 59,965. The relevant conference-paper/article denominator is 63,957; ranked coverage is now 42.11%. Preprints and book chapters are deliberately not assigned journal/conference tiers.

69 reviewed conference aliases inherit the exact conference's CORE2023 tier. Another 54 journal names use the agreed project-defined flagship-journal policy (at least 20 records); these are tagged `custom`, never `core2023`. These journal grades are project judgments, not ratings endorsed by their publishers. Review `added_mappings.csv` and `db/data/manual/venue_tiers.csv` for individual decisions and source URLs. The latter is authoritative for all mappings.

Remaining NULLs include generic publication series (LNCS: 3,058 conference rows), absent venue names (713 conference rows and 1,744 article rows), repositories (e.g. Figshare), companion/extended-abstract proceedings, and conferences without a letter grade in the pinned CORE2023 edition. A series or publisher cannot safely inherit a specific conference's rank. Workshop/companion papers do not automatically inherit the main conference grade.

CORE2023 examples: [RSS is TBR](https://portal.core.edu.au/conf-ranks/1709/), [NSDI is National:USA](https://portal.core.edu.au/conf-ranks/1789/), and [SPAA is B](https://portal.core.edu.au/conf-ranks/1790/). These are not silently replaced with other editions or remembered grades.

`missing_after.csv` contains the remaining venues by paper type and volume. `paper_tier_changes.csv` is the exact paper-level update ledger. `main_apply.json` / `dev_apply.json` record the live updates. The frozen `dedup_series_titles.csv` prevents added tiers from changing previously audited duplicate grouping during future exports.

Custom tiers affect rankings; expose their provenance in the API or filter to `core2023` when only CORE conference grades are desired. NULL means unknown/unmapped, not a zero-quality publication.
