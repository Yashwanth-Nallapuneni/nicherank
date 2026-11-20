# Iteration 2 (continued) — extension from 25 to 52 schools

Naming: this is the second round of the project, continued from the 15 schools added earlier. In the
code it is the batch `iteration3` (`NICHE_SCOPE=iteration3`, files `iteration3_*`) so that it never
rewrites the audited `iteration2_*` decisions for the first 15 added schools. Say "Iteration 2
(continued)" in commits and PRs; the code identifier stays `iteration3`.

Status: school list, rosters and OpenAlex institution IDs are done (rosters only; nothing is loaded
into the database). Identity matching, paper collection, QA and the load are the next steps.

**Schools.** The 27 added schools are `ITERATION3_SCHOOLS` in `script/data/lib/iteration3_rosters.rb`
(CSRankings US top 49, all areas, 2015-2026, checked 2026-11-19; four schools are tied at 49th).
Together with the 25 existing schools the dataset covers 52. Existing schools' rows are never changed.

**Rosters.** `ruby script/data/prepare_iteration3.rb` fetches/parses the official directories registered
in `db/data/manual/iteration3_sources.json` and merges the new schools into `faculty_candidates.csv` and
`faculty_raw.csv`. Pages that scripts cannot fetch (JavaScript lists, HTTP 403, Cloudflare challenge) were
saved from a normal browser into `tmp/iteration3/sources/`; ASU's JavaScript list was rendered with a
headless browser. No CAPTCHA or access-control bypass was used. 1,346 faculty are eligible; 7 without a
listed title are held for review.

## Running the identity and collection steps

All commands run from `data/` with the OpenAlex key exported (never commit it):

```sh
export OPENALEX_API_KEY="$(sed -n 's/^OPENALEX_API_KEY=//p' ../nicherank.env)"
export NICHE_SCOPE=iteration3          # selects the 27 added schools and the iteration3_* files
```

`NICHE_SCOPE` (iteration2 | iteration3) is read by `script/data/lib/iteration_scope.rb`. Each batch has its
own proposal, review, correction and evidence files, so one batch never rewrites another's audited
decisions. The scripts keep their historical `iteration2_` names; without `NICHE_SCOPE` they default to
iteration 2 exactly as before. All steps are resumable from the OpenAlex cache.

| # | Command | Writes |
|---|---|---|
| 1 | `ruby script/data/scan_authors.rb` | `tmp/author_scan/<institution>.json` (cheap list queries) |
| 2 | `ruby script/data/resolve_authors.rb` | `iteration3_author_match_proposals.csv`, `tmp/iteration3/author_resolution/` |
| 3 | `ruby script/data/collect_author_metadata.rb db/data/manual/iteration3_author_match_proposals.csv` | `tmp/author_metadata/<id>.json` |
| 4 | `ruby script/data/iteration2_accept.rb` | accepted rows for the batch in `accepted_author_matches.csv` (other rows untouched, CRLF kept), `iteration3_review.csv` |
| 5 | `ruby script/data/iteration2_retry.rb`, then step 3 for `iteration3_retry_proposals.csv`, then step 4 again | second-pass matches |
| 6 | `ruby script/data/collect_work_pages.rb` | `tmp/work_batches/` (papers, 2015-01-01 to 2026-11-04) |
| 7 | `ruby script/data/iteration2_affiliation_check.rb` | read-only QA of each profile's school affiliation |
| 8 | `ruby script/data/iteration2_aliases.rb`, then step 6 for the accepted aliases | `accepted_author_aliases.csv`, `iteration3_alias_evidence.json` |
| 9 | `ruby script/data/export_full.rb`, `qa_postgres.rb` | export and QA (reads every batch's `*_review.csv`) |
| 10 | back up, tell the team, then `load_postgres.rb --reconcile --prune-withdrawn` | database |

Reviewed corrections go in `db/data/manual/iteration3_identity_corrections.csv` (same columns as the
iteration 2 file). Withheld people are never guessed; they stay in `iteration3_review.csv`.

## Cost

OpenAlex charges per request (searches about $0.001). About 1,350 roster names need roughly 2,000-3,000
requests for matching plus the work collection. A free key allows $1/day; the scripts stop cleanly when the
budget is spent and resume from the cache the next day.
