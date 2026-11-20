# Iteration 2 (continued) — extension from 25 to 52 schools

Naming: this is the second round of the project, continued from the 15 schools added earlier. In the
code it is the batch `iteration2_continued` (`NICHE_SCOPE=iteration2_continued`, files
`iteration2_continued_*`) so that it never rewrites the audited `iteration2_*` decisions of the first
15 added schools.

Status: school list, rosters and OpenAlex institution IDs are done (rosters only; nothing is loaded
into the database). Identity matching, paper collection, QA and the load are the next steps.

**Schools.** The 27 added schools are `ITERATION2_CONTINUED_SCHOOLS` in `script/data/lib/iteration2_continued_rosters.rb`
(CSRankings US top 49, all areas, 2015-2026, checked 2026-11-19; four schools are tied at 49th).
Together with the 25 existing schools the dataset covers 52. Existing schools' rows are never changed.

**Rosters.** `ruby script/data/prepare_iteration2_continued.rb` fetches/parses the official directories registered
in `db/data/manual/iteration2_continued_sources.json` and merges the new schools into `faculty_candidates.csv` and
`faculty_raw.csv`. Pages that scripts cannot fetch (JavaScript lists, HTTP 403, Cloudflare challenge) were
saved from a normal browser into `tmp/iteration2_continued/sources/`; ASU's JavaScript list was rendered with a
headless browser. No CAPTCHA or access-control bypass was used. 1,346 faculty are eligible; 7 without a
listed title are held for review.

## Running the identity and collection steps

All commands run from `data/` with the OpenAlex key exported (never commit it):

```sh
export OPENALEX_API_KEY="$(sed -n 's/^OPENALEX_API_KEY=//p' ../nicherank.env)"
export NICHE_SCOPE=iteration2_continued          # selects the 27 added schools and the iteration2_continued_* files
```

`NICHE_SCOPE` (iteration2 | iteration2_continued) is read by `script/data/lib/iteration_scope.rb`. Each batch has its
own proposal, review, correction and evidence files, so one batch never rewrites another's audited
decisions. The scripts keep their historical `iteration2_` names; without `NICHE_SCOPE` they default to
iteration 2 exactly as before. All steps are resumable from the OpenAlex cache.

| # | Command | Writes |
|---|---|---|
| 1 | `ruby script/data/scan_authors.rb` | `tmp/author_scan/<institution>.json` (cheap list queries) |
| 2 | `ruby script/data/resolve_authors.rb` | `iteration2_continued_author_match_proposals.csv`, `tmp/iteration2_continued/author_resolution/` |
| 3 | `ruby script/data/collect_author_metadata.rb db/data/manual/iteration2_continued_author_match_proposals.csv` | `tmp/author_metadata/<id>.json` |
| 4 | `ruby script/data/iteration2_accept.rb` | accepted rows for the batch in `accepted_author_matches.csv` (other rows untouched, CRLF kept), `iteration2_continued_review.csv` |
| 5 | `ruby script/data/iteration2_retry.rb`, then step 3 for `iteration2_continued_retry_proposals.csv`, then step 4 again | second-pass matches |
| 6 | `ruby script/data/collect_work_pages.rb` | `tmp/work_batches/` (papers, 2015-01-01 to 2026-11-04) |
| 7 | `ruby script/data/iteration2_affiliation_check.rb` | read-only QA of each profile's school affiliation |
| 8 | `ruby script/data/iteration2_aliases.rb`, then step 6 for the accepted aliases | `accepted_author_aliases.csv`, `iteration2_continued_alias_evidence.json` |
| 9 | `ruby script/data/export_full.rb`, `qa_postgres.rb` | export and QA (reads every batch's `*_review.csv`) |
| 10 | back up, tell the team, then `load_postgres.rb --reconcile --prune-withdrawn` | database |

Reviewed corrections go in `db/data/manual/iteration2_continued_identity_corrections.csv` (same columns as the
iteration 2 file). Withheld people are never guessed; they stay in `iteration2_continued_review.csv`.

## Cost

OpenAlex charges per request (searches about $0.001). About 1,350 roster names need roughly 2,000-3,000
requests for matching plus the work collection. A free key allows $1/day; the scripts stop cleanly when the
budget is spent and resume from the cache the next day.
