# NicheRank QA — audited revision 2

This report supersedes the initial delivery. Snapshot cutoff: **2026-11-04 (America/New_York)**. Main and dev contain the corrected dataset. No per-person collection cap; high-risk mixed profiles have explicit evidence-based withholding.

## Final counts

- Schools: **10**
- Faculty: **1,126**
- Papers: **86,898**
- Authorships: **103,879**
- Accepted alias links: **101**
- Deduplicated source IDs retained as trace: **2,013**
- Papers with abstracts: **74,382 (85.6%)**
- Current export review cases: **8,740**
- Database review history: **8,966** including 226 preserved earlier cases; superseded cases are retained as provenance

| School | Faculty | Distinct papers | Authorships |
|---|---:|---:|---:|
| Carnegie Mellon University | 295 | 23701 | 27220 |
| Cornell University | 86 | 5042 | 5470 |
| Georgia Institute of Technology | 131 | 9680 | 10315 |
| Massachusetts Institute of Technology | 143 | 13945 | 15319 |
| Stanford University | 67 | 8168 | 9068 |
| University of California Berkeley | 79 | 7981 | 9002 |
| University of California San Diego | 69 | 6089 | 6504 |
| University of Illinois Urbana-Champaign | 119 | 9441 | 10086 |
| University of Michigan | 61 | 3593 | 3821 |
| University of Washington | 76 | 6313 | 7074 |

School counts overlap for cross-school coauthorship.

## Tests and database checks

**32 tests / 102 assertions, zero failures/errors.** Both branches passed final QA: no broken foreign keys, duplicate authorship pairs or normalized DOIs, alias/canonical collisions, unlinked papers, invalid paper types, missing rank provenance or incorrect weighted search vectors. Entity/link counts match the export. Preserved historical review cases are separately enumerated.

The v1-to-v2 reconciliation was tested on a fresh local restore and repeated; the second load changed zero entity/link rows. Existing numeric professor IDs remain stable across canonical-ID corrections. Main/dev may have different numeric IDs because they were independently loaded; OpenAlex natural keys are used to compare their data.

Both reader connections successfully search **86,898 papers**, including 5,949 hits for `robot learning`. SELECT is allowed; INSERT and schema CREATE are denied. The old application password remains unchanged, per Suhruth's instruction.

The final PostgreSQL 17 archive is taken from **main**, is **43,255,339 bytes**, and passed both archive-list and fresh restore verification. All seven restored table counts match main. SHA-256: `96a41c8e5d1cc256927744dcb662bfff9346a5f17504e0b0060ac4e2349f8127`. Ownership/grants and role passwords are not included. The temporary restore instance was stopped and removed.

## The three data-quality checks

See **[the detailed audit](reports/audit/AUDIT_REPORT.md)** and its evidence files.

1. **Author accuracy:** screened all 1,116 original profiles and selected 3,316 sample pairs. Independently corroborated paper samples for 731 original profiles using faculty-linked pages or publisher name plus ORCID/institution evidence. Corrected four canonical selections. Other sample outcomes remain inconclusive; this is not universal manual verification. Eleven high-risk mixed profiles use title/DOI-supported curation and NULL unknown career metrics.
2. **Coverage:** resolved ten of thirteen missing identities. The revised roster has 1,126 matched out of 1,129 eligible entries after the deceased memorial exclusion. Adam Paulisick, Ana Maria Pinto da Silva and Merrick Furst remain unresolved; the separate 25 CMU eligibility cases remain omitted as agreed. Three original zero-paper cases were fixed; Ari Lightman remains zero in the checked qualifying corpus, not certified publication-free.
3. **Aliases and duplicates:** rechecked all 97 original aliases with other-coauthor IDs and independent publication evidence. Four earlier alias links were removed, including one attached to the wrong Xiuwei identity; eight manually evidenced additions yield 101. Uncertain Barrett/Goodman/Wu aliases remain unmerged. All 2,013 current merge decisions passed the stricter criteria. All 8,237 collision-pair cases were classified and kept separate; 1,287 previously discarded IDs are now retained. Distinct formal DOIs and generic/series titles no longer merge on title/year/author alone.

Current accepted alias evidence is `db/data/manual/accepted_alias_evidence_v2.json`; the earlier name-based alias evidence is historical and is not the approval authority. The legacy proposal script no longer overwrites accepted aliases.

## Limits and usage

Dataset completeness remains **false**. Three identity gaps, inconclusive samples, partial curated bibliographies, unsupported alias candidates and conservative version handling remain explicitly documented. An uncorroborated title is not automatically declared false. Current affiliation groups historical publications. Generic/unverified venues retain NULL tiers; custom journal ranks remain project policy, not CORE journal ranks.

Final OpenAlex usage: **$0.6943 of the free $1 daily allowance**, with $0.3057 remaining and no prepaid balance. Publisher checks used Crossref's public metadata API. No paid model API calls were used. Source/API responses were cached; caches and credentials are excluded from Git and the delivery ZIP.

## Venue/vector delivery update — 2026-11-05

See `DELIVERY.md` for the latest dump and rebuild command, and `reports/venues/TIER_COVERAGE.md` for the tier refresh. Both branches have pgvector 0.8.0. Required schema names remain unchanged. Live counts: 10 schools, 1,126 professors, 86,898 papers, 103,879 authorships, 101 aliases, 2,013 duplicate trace rows and 9,089 review-history rows (8,740 current export cases). Latest Ruby checks: 34 tests / 104 assertions passed. Fresh restore/rebuild QA files under `reports/venues/` supersede earlier delivery verification.
