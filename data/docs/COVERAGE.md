> Historical sample/preparation notes. Superseded by `../HANDOFF_FOR_YASHWANTH.md`, `../SCHEMA.md`, and `../QA.md`.

# Data coverage — November 4, 2026

The account-free preparation and connected real import sample are complete. The full publication dataset and Rails import remain unfinished and require the next phase.

## Official faculty directory extraction

All ten agreed schools were processed, with official source links and eligibility decisions preserved. These are **rule-filtered roster records**, not 1,130 individually verified OpenAlex identities.

| University | Included by eligibility rules | Excluded by rules | Unresolved eligibility |
|---|---:|---:|---:|
| Carnegie Mellon University | 297 | 175 | 25 |
| Cornell University | 86 | 58 | 0 |
| Georgia Institute of Technology | 133 | 16 | 0 |
| Massachusetts Institute of Technology | 143 | 11 | 0 |
| Stanford University | 67 | 27 | 0 |
| University of California Berkeley | 79 | 49 | 0 |
| University of California San Diego | 69 | 8 | 0 |
| University of Illinois Urbana-Champaign | 119 | 35 | 0 |
| University of Michigan | 61 | 85 | 0 |
| University of Washington | 76 | 19 | 0 |

Totals: **1,638 directory candidates, 1,130 included roster records, 483 excluded, 25 unresolved**. The 25 unresolved appointments are at CMU, mostly contingent/special faculty or administrative titles that do not establish eligibility. They are omitted from `faculty_raw.csv` and retained in `faculty_candidates.csv` and `review.csv`; do not guess their ranks or primary appointments. This follows the agreed handoff rule allowing documented unresolved cases.

Directory pagination was checked: Stanford pages 0–2 contain 94 entries and page 3 is empty; Georgia Tech's scoped pages 0–12 contain 149 entries and page 13 is empty. Cornell's explicit CS department filter returns all 144 department/field/other entries in one response; only eligible department appointments are included. CMU's public all-SCS faculty/staff feed was filtered to Faculty in the seven agreed computing units. MIT uses the union of CS and AI+D. Berkeley uses its CS faculty list. Illinois uses its school faculty view. Washington and Michigan use their full faculty directories. UCSD ranks were cross-checked against its engineering CSE listing and specific official/linked profiles.

Direct script access to Michigan returned HTTP 403; its public directory loaded in the normal browser and was saved from the rendered page. No CAPTCHA, login, or access-control bypass was used. A downloaded source snapshot is included in the raw-source archive. Refreshing that one snapshot may require a normal browser download again.

Faculty names and appointment labels are only as current as the sources served. This is current roster membership, not university affiliation at the publication date. Explicit joint appointments may be included; courtesy-only appointments are excluded. Clinical professional/teaching-track titles are excluded by a documented local decision. Source discrepancies and overrides are in `faculty_overrides.csv`. For example, UCSD's engineering list identifies some CS-directory names as adjunct/emeritus; those entries are excluded.

## Verified institution identities

All ten main-campus OpenAlex institution IDs have been verified by university name and city, excluding medical centers and other campuses. See `institution_verification.csv` for IDs and ROR/source evidence.

## Venue mappings

- Official CORE2023 export: **956 records**.
- Eligible A*/A/B/C conference records: **759**.
- Final exact-name/acronym mapping rows: **1,513**, including four custom journal name/acronym rows.
- Nine ambiguous mapping rows are held out in `venue_mapping_conflicts.csv`.
- JMLR and TPAMI receive custom A* tiers under the teammate's journal-tier policy. These are **not CORE journal rankings**.
- No fuzzy or inferred conference acronym matching is enabled. The high-frequency unmatched-venue review depends on the future full publication collection.

## Real connected sample

- 10 verified university rows; the faculty/paper sample is from Stanford only.
- 20 reviewed canonical author matches.
- Two verified same-ORCID aliases; canonical profiles have more qualifying works since 2015.
- 43 real papers and 43 selected-professor authorships.
- Abstract coverage: **97.67%**.
- At most two recent qualifying works per canonical/verified alias profile. This is an importer/search smoke-test sample, not complete bibliographies or a user-study evaluation corpus.
- Three unresolved potential-alias cases remain in manual review. One possible paper duplicate is reported by the sample exporter, leaving 29 rows in the sample review file including the 25 faculty-eligibility cases.

Identity evidence is in `author_match_checks.csv`; the review inspected name, institutional connection, research topics, and recent papers. Alias searches were bounded to the first ten institution-filtered and wider name results. Those searches do not prove the absence of further aliases. Source metrics and publication dates may contain source errors.

The sample was obtained through public key-free basic lookups. No cursor pagination or paid API usage was used. Public API responses have been imported into the collector cache for reuse.

## API corrections established during preparation

1. Supported page size is 100; 200 is deprecated.
2. OpenAlex now uses `conference-paper`, and rejects `proceedings-article` as a type filter. The collector filters on the current value and maps it to `proceedings-article` in the CSV to preserve the teammate's contract.
3. Canonical works author filter is `authorships.author.id`.
4. Full cursor pagination still requires a key; no key has been configured.

## Verification

- Ruby 3.3.12: **26 offline tests, 82 assertions, zero failures/errors**.
- Real sample CSV headers, IDs, references, booleans, relationships, and duplicates pass local validation.
- A simulated collection-to-export integration and snapshot re-export pass.
- A synthetic 50,000-paper export plus validation took 2.47 seconds locally. This does not measure network or human-review time; synthetic data was removed.
- The actual private Rails importer has not been inspected or executed. Exact backend compatibility awaits repository access and Yashwanth's import check.

## Remaining work

**With OpenAlex key:** resolve the remaining roster members to author IDs, review potential aliases, paginate all qualifying papers since 2015, run full-corpus deduplication and venue review, and export the complete dataset. Some identity cases may remain documented for Yashwanth's review under the agreed policy.

**With repository access:** inspect the real importer, transfer the collector/sample/manual files, reconcile any contract differences, and verify the real Rails import. PostgreSQL/migrations/importer belong to Yashwanth.

**Before final delivery:** obtain the agreed deadline and Drive destination, complete the required full-dataset spot checks and coverage review, and upload only to the agreed destination. No external upload or message has been sent.
