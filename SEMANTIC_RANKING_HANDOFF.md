# Semantic ranking handoff

Branch `feature/semantic-ranking` (not merged into `main`). Built on the semantic search in `SEMANTIC_SEARCH_HANDOFF.md`. Owner: Suhruth.

## What it does

A search in **Meaning (semantic)** or **Both (hybrid)** mode now also ranks universities **for that topic**. The rankings list is headed "Rankings for “query”" and ranks universities by their papers closest in meaning to the search, instead of by whole research areas.

- **Show faculty** lists only professors with papers on the topic, strongest first, each with a topic score.
- **View papers** shows that professor's papers on the topic, most relevant first, with a "Papers on “query”" line.
- **Keyword** mode and the plain rankings page work exactly as before.
- **Fallback:** if Voyage or the embeddings table fails, the page shows the plain ranking with the existing "Search by meaning is unavailable right now" notice.

## How the score works

`app/models/topic_ranking.rb` (`TopicRanking < Ranking`):

1. **Which papers.** Same as the plain ranking: conference papers and articles, in the selected years, at venues of the selected areas (`Ranking#eligible_papers`). So the year and area filters apply.
2. **Nearest papers.** The `POOL = 500` qualifying papers whose embeddings are nearest the query, by cosine similarity.
3. **Cutoff.** Keep papers within `BAND = 0.08` below the `ANCHOR = 10`th best match.
   - It's relative because similarity values differ from query to query.
   - It's measured from the 10th match, not the 1st, so one near-duplicate of the query can't shrink it.
   - When there are fewer than 10 candidates, it's measured from the best match.
4. **Weight.** 1 at or above the anchor, falling linearly to 0 at the edge of the band.
5. **Credit.** Each paper's weight is split equally among its roster-faculty authors, the same split the plain ranking uses for its 1 point per paper. A university's score is the sum of its professors' shares, so a paper shared inside one university is never counted twice.
6. **Display.** Ranks and the "Sort institutions" options work as in the plain ranking.

On the 52-school data, step 3 keeps about 100–450 papers per topic.

## Files changed

| File | Change |
|---|---|
| `app/models/topic_ranking.rb` | New. The topic ranking. |
| `app/models/ranking.rb` | `eligible_papers` split out of `papers`; `topic` (nil for the plain ranking). |
| `app/models/paper.rb` | `query_vector`; `semantic_ids` / `hybrid_ids` take an optional `vector:` so a request calls Voyage only once. Behaviour unchanged. |
| `app/controllers/rankings_controller.rb` | Meaning/hybrid search builds a `TopicRanking`; falls back to `Ranking`. |
| `app/controllers/professors_controller.rb` | With `q` + `mode`, lists the professor's topic papers; falls back to all papers. |
| `app/views/rankings/index.html.erb` | "Rankings for …" heading and explanation, faculty topic score. |
| `app/views/professors/show.html.erb` | "Papers on …" line with the professor's topic score. |
| `SEMANTIC_SEARCH_HANDOFF.md` | Short "Semantic ranking" section; two known limits updated. |

## Performance

- **One Voyage call per request.** The query vector is fetched once and shared by the paper search and the ranking.
- **Exact vector search.** It scans the qualifying papers exactly (`ORDER BY (distance) + 0`), because the HNSW index would search all 220k+ papers first and drop the ones outside the filters, returning too few.
- **Speed.** About 0.7–0.9 s per page on the 52-school data. The ranking isn't cached, so it's recomputed on every page view.

## Checked on real data

Read-only, against the Heroku database. A Voyage key wasn't available, so each query vector was the average of several on-topic papers' embeddings.

| Topic | Top universities (top professor) |
|---|---|
| robot manipulation | CMU (Kroemer), UW (Fox), Stanford (Bohg), MIT (Tedrake), Berkeley (Abbeel) |
| differential privacy | UVA (Tianhao Wang), Cornell (Hsu), Penn State (Kifer), Harvard (Vadhan), BU (Adam Smith) |
| query optimization | Penn (Ryan Marcus), Cornell (Trummer), USC (Sabek), MIT (Kraska), Duke (Jun Yang) |
| graph neural networks | UIUC (Hanghang Tong), Texas A&M (Azad), Purdue (Neville), Michigan (Koutra), NC State (Xiaorui Liu) |

## Tests

```sh
unset DATABASE_URL
export TEST_DATABASE_URL="postgres://$(whoami)@127.0.0.1:5434/nicherank_test"
RAILS_ENV=test bundle exec rspec
RAILS_ENV=test bundle exec cucumber
```

- **RSpec:** `tests/spec/models/topic_ranking_spec.rb` (9 examples). They cover ranking by relevance rather than paper count, the band cutoff, the anchor, author splits within one university, the year and area filters, papers without embeddings, faculty and paper order, and the institution sort.
- **Cucumber:** `tests/features/semantic_ranking.feature`, story 14 (3 scenarios): the topic ranking replaces the area ranking, faculty and professor papers follow the topic, and the fallback works when Voyage is down.
- **Result:** 82 RSpec examples and 33 Cucumber scenarios pass. `save_institutions.feature:75` ("Explain storage failures…") fails sometimes; it fails about 3 times in 8 on `main` too, so it isn't caused by this branch.

No test calls Voyage; query vectors are stubbed as in the semantic search tests.

## Not done / next steps

- **Re-check `BAND` with real typed queries.** Query embeddings (`input_type: "query"`) may sit at different similarity levels than the averaged paper vectors used here. Look at how many papers `TopicRanking#relevance` keeps for a handful of searches. About 100–450 is the target.
- **Ranking signals.** Recency, venue tier (`venue_rankings`) and author position (`authorships.position`) aren't used in the score yet.
- **Caching.** Cache the ranking per query and filter set if the page feels slow.
- **Merging.** Not merged into `main`, so the live site doesn't have it yet.
