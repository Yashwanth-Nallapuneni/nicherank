# NicheRank collection and database QA

Snapshot cutoff: **2026-11-04**, America/New_York calendar date. Source retrieval timestamps are UTC. No per-person paper cap. Main and dev both loaded and checked. This report describes available matched profiles; **100% faculty/bibliography coverage is not certified**.

## Delivered database

- Universities: **10**
- Professors: **1,116** (including four with zero qualifying publications)
- Unique retained papers: **85,471**
- Authorships: **102,049**
- Verified alias links: **97**
- Discarded duplicate IDs retained as provenance: **3,277**
- Abstracts: **73,198 / 85,471 (85.64%)**; unknown abstracts remain NULL
- Database review cases: **6,987**, including one preserved historical sample venue case; the current export has 6,986 cases

| School | Professors | Distinct papers | Authorships |
|---|---:|---:|---:|
| Carnegie Mellon University | 295 | 23464 | 26949 |
| Cornell University | 85 | 4954 | 5375 |
| Georgia Institute of Technology | 128 | 9485 | 10106 |
| Massachusetts Institute of Technology | 143 | 13662 | 15007 |
| Stanford University | 67 | 7961 | 8813 |
| University of California Berkeley | 79 | 7896 | 8913 |
| University of California San Diego | 68 | 5985 | 6394 |
| University of Illinois Urbana-Champaign | 116 | 9203 | 9838 |
| University of Michigan | 59 | 3474 | 3670 |
| University of Washington | 76 | 6231 | 6984 |

School counts overlap because papers may have authors from multiple schools.

## Passed checks

Main and dev each passed: no broken professor/university, authorship or alias foreign keys; no duplicate authorship pairs or normalized DOIs; no alias/canonical ID collisions; no unlinked papers; valid `paper_type` values; rank provenance present when ranked; every generated search vector exactly matches the agreed A/A/B/C expression. Entity and relationship counts match the export. One pre-existing arXiv venue review case is intentionally preserved outside the current export; it is not a data-count defect.

Both read-only connections use `nicherank_reader`: SELECT allowed, INSERT and schema CREATE denied. A `robot learning` keyword query returns 5,916 papers on each branch. The schema, columns and GIN index are already installed. The earlier application password was not rotated, per Suhruth's request.

Offline automated tests: **28 tests / 92 assertions, zero failures or errors**. The Ruby COPY loader was tested on dev with the sample before loading the expanded dataset. Both full loads completed transactionally.

The PostgreSQL 17 custom archive is **42,481,952 bytes**. Its archive listing and a full restore into a fresh local PostgreSQL 17 instance passed; restored entity/link counts match Neon. SHA-256: `0e8b4e5664c30612916205da1b8f228e441053c252d9f47fecc07d58133f8b6b`. The temporary restore server was stopped and removed.

## Coverage exceptions and source quality

The extracted roster has 1,130 included entries. One deceased Georgia Tech memorial entry (Alberto Apostolico, 1948–2015) was excluded, leaving 1,129 eligible roster entries for identity matching. **1,116 matched, 13 unresolved**. The separate 25 unresolved CMU eligibility cases remain omitted as agreed; clinical/teaching-track and unit exclusions remain documented in the source roster audit.

Unresolved identities:

- Carnegie Mellon University: Adam Paulisick
- Carnegie Mellon University: Ana Maria Sande do Vale Pinto da Silva
- Cornell University: Michael Kim
- Georgia Institute of Technology: Merrick Furst
- Georgia Institute of Technology: Qi Tang
- Georgia Institute of Technology: Steve Mussmann
- Georgia Institute of Technology: Will Perkins
- University of California San Diego: Yiying Zhang
- University of Illinois Urbana-Champaign: Bo Li
- University of Illinois Urbana-Champaign: Gang Wang
- University of Illinois Urbana-Champaign: Hao Peng
- University of Michigan: Ryan Huang
- University of Michigan: Wei Hu

These 13 are not loaded under guessed IDs. Some verified individual publications were found, but a reliable complete author profile could not be established. Their exclusion is a coverage limitation, not a claim that they have no publications. Automated matches were screened by name, institutional evidence and topic review, with manual corrections; the entire roster was not individually human-verified.

The three previously uncertain Barrett/Goodman/Wu aliases remain unmerged. Primary ORCID candidate splits were merged only with compatible display names and at least two shared coauthors (plus the two previously verified sample aliases). Different-ORCID and unsupported candidates remain unmerged; no claim of exhaustive alias coverage is made. Evidence is in `db/data/manual/verified_alias_evidence.json` and the earlier alias review files.

Publication collection yielded 89,724 distinct raw work IDs before filtering/deduplication. Of these, 937 had no retained selected-author link and 39 lacked a usable title; those records were not assigned by guesswork. Remaining records were deduplicated conservatively by normalized DOI or compatible same-title/year/selected-author evidence. Possible title collisions were kept separate.

Current export review cases: 6,491 possible duplicate-pair cases, 449 high-frequency unmatched venue cases, 25 eligibility cases, 16 author/alias cases, four zero-paper professors, one deceased-faculty exclusion. These cases are **not all resolved**. Many title collisions involve generic titles; source records stay separate unless the conservative merge rule passes. Generic series/repositories and unverified venues retain NULL tiers. The preserved earlier sample duplicate also remains separate where the merge rule fails.

There are 1,538 exact venue mappings. Explicit CORE2023 conference aliases use `core2023`; project-assigned journal tiers use `custom`. New custom journal mappings each have at least 20 retained papers. JMLR/TPAMI follow the separately approved existing policy. Workshops, findings and extended abstracts do not inherit the parent conference tier.

OpenAlex can contain profile misattributions, truncated/unlinked authorships and missing publications. This release is useful for iteration-1 keyword search, but does not certify complete or error-free bibliographies or authoritative school rankings. Current affiliation groups historical papers under the current school.

## Usage and artifacts

OpenAlex reported **$0.668 of the free $1 daily allowance used**, $0.332 remaining, and no prepaid balance at the final check. No paid credits or model API calls were used. Exact response caching and incremental author batches avoided repeat collection.

Machine-readable QA, dataset and dump manifests are in `reports/`. Full CSVs and the database archive are delivered separately, outside Git. Raw source/API caches stay local and are excluded from the delivery repository.
