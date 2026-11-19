# Iteration 2 — extension from 10 to 25 schools

Prepared 2026-11-15 on branch `data-iteration2-25-schools`. **Loaded into Neon `dev` only; `main` is unchanged and still holds the 10-school delivery.** The schema is unchanged (version 2), so no backend field names change and the same queries work.

## Schools added

Fifteen US schools join the original ten. Together they are the CSRankings top 25 (US, all areas, 2015–2026, checked 2026-11-15):

UMD, Northeastern, Purdue, NYU, UT Austin, UW–Madison, Princeton, Penn, Columbia, UCLA, USC, UChicago, UMass Amherst, UC Irvine, Stony Brook.

The publication window and snapshot cutoff match the original delivery: 2015-01-01 through **2026-11-04**. There is no per-person paper cap.

## Result (dev)

| Entity | 10 schools (main) | 25 schools (dev) |
|---|---:|---:|
| Universities | 10 | 25 |
| Professors | 1,126 | 2,157 |
| Papers | 86,898 | 149,932 |
| Authorships | 103,879 | 184,759 |
| Verified author aliases | 101 | 119 |
| Duplicate trace rows | 2,013 | 3,486 |

Dev QA (`qa_dev.json`) passed:
- Zero broken foreign keys, duplicate authorship pairs, duplicate DOIs, alias collisions, unlinked papers, invalid paper types, tiers without provenance or incorrect search vectors.
- Every database count equals the export manifest.

Per-school counts are in `qa_dev.json`. Dev was backed up before loading. The backup is private and untracked: `tmp/delivery/iteration2/dev_before_25school_load.dump`.

## Original ten schools

Every baseline roster, match and alias row is byte-identical, and all 1,126 professor rows are unchanged. The exporter reads the original collection batches first, so later re-downloads of shared works cannot drift frozen metadata. Intended or expected differences in baseline papers:

- **741 papers gained a venue tier** from the new CORE2023 conference aliases below.
- **41 authorships added.** These papers are dated within the window but entered OpenAlex after the first collection; they appeared through new-school coauthors.
- **7 papers merged as duplicates** of a newly collected version (title-safe deduplication). They remain traceable in `paper_duplicates`, and professors keep credit through the retained record. One merged group now shows the highest citation count in the group (dedup rule).
- **Net effect:** at most a few papers more per original school; professor counts unchanged.

## Method for the new schools

1. **Rosters.** Only official department directories are used (`public_sources.json`, with retrieval time and SHA-256); the parsers are in `script/data/lib/iteration2_rosters.rb`. Scope is the CS department or college faculty list, for example NYU Courant CS plus Tandon CSE, UC Irvine CS plus Informatics, and Khoury tenure-track plus research faculty. Secondary, affiliate, adjunct, emeritus and memorial directory sections are kept as excluded evidence rows. Two people listed by both NYU units are counted once.
2. **Eligibility.** The already-confirmed scope applies: tenure-track or research faculty. Clinical, teaching-track, emeritus, adjunct, visiting, courtesy, affiliate, joint-only, postdoc, memorial and not-yet-started appointments are excluded. Of 11 unclear directory titles, 9 were resolved from official profile pages (`faculty_overrides.csv`). Two (Keith Marzullo, Vijay Kumar) stay open because their pages show administrative titles only.
3. **Identity, first pass.** An institutional OpenAlex scan plus targeted searches (`scan_authors.rb`, then `resolve_authors.rb` with `NICHE_SCOPE=iteration2`).
4. **Identity, second pass (`iteration2_retry.rb`).** Name variants are searched. A profile is accepted only when all of these hold:
   - its display name matches;
   - it has an OpenAlex affiliation with the school in 2020 or later;
   - Computer Science or Mathematics is among its top-3 topics;
   - it has 5–600 works;
   - and it is the only such profile, shares the rival profiles' ORCID, has 5x the works of any rival, or shares at least 3 coauthors with every rival (one person split by OpenAlex).

   Recent hires whose OpenAlex affiliation still shows a previous school were accepted only as the single exact-name computing profile, and each was reviewed. This pass added 55 professors.
5. **Safeguards and review (`iteration2_accept.rb`, `iteration2_identity_corrections.csv`).** The script withholds:
   - an ID already used by another professor or proposed twice;
   - a profile with no OpenAlex affiliation with the school (except reviewed recent hires);
   - a profile with over 2,000 works.

   Two reviewed checks then ran over **all** new matches:
   - a **topic check** for profiles whose top topics are not computing;
   - a **paper-level affiliation check** (`iteration2_affiliation_check.rb`): how many of each professor's own papers list the school.

   Together with the second-pass review, these produced 3 replacements with the correct profile and 34 withheld wrong-person, merged or unreliable profiles, each recorded with a reason. **1,031 professors accepted**. 1,001 have at least one collected paper listing their school; the rest are mostly reviewed recent hires or have no qualifying papers.
6. **Aliases (`iteration2_aliases.rb`).** Same rule as the baseline: same primary ORCID, a compatible name and at least two shared coauthors. 18 accepted (`iteration2_alias_evidence.json`).
7. **Venue tiers (`iteration2_venue_aliases.rb`).** This added 87 exact OpenAlex display names that are aliases of a letter-graded CORE2023 conference. The CORE title must match, and workshop, companion, Findings and demo venues never inherit a grade. The 139 rejected candidates (no letter grade, acronym collisions such as ICCP and ICNC, ambiguous entries) are listed with reasons in `venue_rejected_candidates.csv`. **No new custom journal tiers were added**, because those need backend-team approval. `journal_tier_candidates.csv` lists 325 unranked journals with 20+ articles for that decision.
8. **Collection, export and load.** `collect_author_metadata.rb`, `collect_work_pages.rb` and `export_full.rb` run first. Then `load_postgres.rb --reconcile --prune-withdrawn` loads dev. The new `--prune-withdrawn` flag removes professors of a staged school who are no longer in the export, plus their links; it never touches schools absent from the export. QA (`qa_postgres.rb`) runs last.

## Venue-tier coverage (25 schools)

| Paper type | Ranked | Coverage | 10-school delivery |
|---|---:|---:|---:|
| conference-paper | 34,188 / 64,169 | 53.28% | 53.57% |
| article | 11,765 / 46,795 | 25.14% | 26.60% |
| preprint, book chapter | 0 | 0% by policy | 0% |

Remaining NULLs are mostly generic series (LNCS), Findings, companion and workshop proceedings, repositories, and venues without a CORE2023 letter grade (for example MICRO, DAC and RSS are TBR in the pinned edition). Journal coverage stays lower until custom journal tiers are approved.

## Open review cases (`iteration2_review.csv`)

79 open cases, all withheld rather than guessed:
- **41 no unambiguous profile.** These are mostly very common names (for example Wei Xu, Hao Zhang and Xi Chen variants) or very new faculty.
- **35 withheld after review.** These are wrong-person, merged or unreliable profiles, each with a stated reason. Examples: Robert Rand, Brendan O'Connor, Kai Li, Lixia Zhang and Zhong-Ping Jiang.
- **Jesse Thomason (USC):** the matching OpenAlex ID is already the accepted profile of a Jesse Thomason in the **Georgia Tech** baseline roster. The baseline row was not changed; the Georgia Tech entry should be checked.
- **2 eligibility cases:** Keith Marzullo and Vijay Kumar.

## Known limitations (do not overstate coverage)

- New-school identities rest on automated matching plus the checks above, not the original ten's sample-corroboration audit. Some wrong matches between same-name computing researchers may remain, especially for profiles with few papers.
- Some correct profiles are partial: OpenAlex splits a person and the alias rule did not merge them (for example Xia Zhou, Sharon Li and Jerry Zhu have small profiles). Their paper counts are undercounts.
- Directory scope differs by school (UC Irvine includes Informatics; Penn uses primary CIS faculty only), as recorded in each roster unit.
- NicheRank counts will not match CSRankings, which uses its own faculty lists and venue set.

## Not done yet

- Load into Neon `main`, at a time agreed with the backend owner, because `main` is the live backend database. Back up first, then run `ruby script/data/load_postgres.rb data/output/full /private/path/owner-main.env --reconcile --prune-withdrawn`, then `qa_postgres.rb`.
- Decide custom tiers for any of the journals in `journal_tier_candidates.csv`.
- A new private delivery ZIP and dump for this final export. The earlier dev dump predates the review work.
