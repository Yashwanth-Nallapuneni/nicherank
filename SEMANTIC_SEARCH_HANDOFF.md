# Semantic search handoff

What is live on `main` and Heroku (`nicherank-app`) as of commit 13c90da, and what you need to build semantic ranking on top of it.

## What it does

The search box has three modes (`RankingsController::MODES`):

| Mode | Label on the site | How papers are ranked |
|---|---|---|
| `keyword` | Keyword | Postgres full-text search (`papers.search_vector`, `ts_rank`). Unchanged from Iteration 1. |
| `semantic` | Meaning (semantic) | The 200 papers whose embeddings are closest to the query's embedding (cosine distance). |
| `hybrid` | Both (hybrid) | Top 200 keyword hits and top 200 semantic hits merged with Reciprocal Rank Fusion. |

Semantic and hybrid results reuse the normal results table, sort options and pagination.

## How it works

**Offline (once per paper).** Each paper's title and abstract (`PaperEmbedding.text_for`, abstract cut at 6,000 characters) is sent to Voyage AI, model `voyage-4-lite`, 512 dimensions, `input_type: "document"`. The vector is stored in `paper_embeddings`. All 223,694 papers in `nicherank-db` are embedded.

**Per search.**
1. The query is cut to 300 characters and embedded with the same model (`input_type: "query"`). `Paper.query_embedding` caches it in `Rails.cache` for a week, so repeating a search makes no API call.
2. `Paper.semantic_ids` runs `ORDER BY embedding <=> query_vector LIMIT 200` on `paper_embeddings`. `<=>` is pgvector's cosine distance; the HNSW index makes this a few milliseconds. `hnsw.ef_search` is raised to 400 inside the transaction so all 200 neighbours come back.
3. Hybrid only: `Paper.hybrid_ids` scores each paper as the sum of `1 / (60 + rank)` over the keyword list and the semantic list, then keeps the top 200. Ranks are used instead of raw scores because `ts_rank` and cosine distance are not on the same scale. A paper ranked high in both lists wins.
4. `Paper.ranked_page` loads one page of those ids in ranked order (`array_position`), or in the chosen sort.

**Failure handling.** If Voyage errors or times out (3 s, no retries on the request path) or the embeddings table can't be read, `RankingsController#meaning_search` logs it and shows keyword results with the notice "Search by meaning is unavailable right now, so these are keyword results."

## Files

| File | What it holds |
|---|---|
| `app/models/voyage_client.rb` | HTTP client for the Voyage embeddings API. Retries 429/5xx and network errors when `retries:` is given. |
| `app/models/paper_embedding.rb` | Model for `paper_embeddings`; `text_for` defines the exact embedded text. Changing it means re-embedding every paper. |
| `app/models/paper.rb` | `semantic_ids`, `hybrid_ids`, `ranked_page`, `query_embedding` (constants `SEMANTIC_LIMIT = 200`, `RRF_K = 60`). |
| `app/controllers/rankings_controller.rb` | Mode selection, `MAX_QUERY`, keyword fallback. |
| `db/paper_embeddings.sql` | Creates the table and HNSW index. Additive and safe to re-run. |
| `lib/tasks/embeddings.rake` | `create_table`, `status`, `backfill`. |

## Database

Table in `nicherank-db` (additive, no existing table changed):

```sql
paper_embeddings (
  paper_id    bigint PRIMARY KEY REFERENCES papers(id) ON DELETE CASCADE,
  embedding   vector(512) NOT NULL,
  model       text NOT NULL,
  embedded_at timestamptz NOT NULL DEFAULT now()
)
-- index: hnsw (embedding vector_cosine_ops)
```

About 1.2 GB with the index. Rails reads the vector column as a string (`"[x,y,...]"`), so the "unknown OID" warning in logs is expected.

## Keeping embeddings current

New papers are invisible to semantic search until they are embedded. After any data load, run against the real database:

```sh
export DATABASE_URL="$(heroku config:get DATABASE_URL -a nicherank-db)"
export VOYAGE_API_KEY="$(heroku config:get VOYAGE_API_KEY -a nicherank-app)"
bin/rails embeddings:status                  # how many papers are missing
DRY_RUN=1 bin/rails embeddings:backfill      # token estimate, no API calls
bin/rails embeddings:backfill                # embeds only missing papers; safe to re-run
```

Papers Voyage rejects on their own are skipped and listed, so one bad text can't block the run. To re-embed a paper, delete its row and run the backfill again.

Do not save either value in a file or in the repo. Heroku can rotate the database password, so fetch it each time.

## Running locally

```sh
export DATABASE_URL="$(heroku config:get DATABASE_URL -a nicherank-db)"
export VOYAGE_API_KEY="$(heroku config:get VOYAGE_API_KEY -a nicherank-app)"
bin/rails server
```

This login can write to the live database the site uses. No schema changes without checking with Suhruth and Joon; new tables only.

Without `VOYAGE_API_KEY`, semantic and hybrid fall back to keyword search.

## Tests

No test calls Voyage. `tests/spec/support/embedding_helpers.rb` builds hand-made 512-dim vectors (`concept_vector`, `embed_paper!`) and stubs `Paper.query_embedding` (`stub_query_embedding`). The test database needs pgvector (README has the setup).

- `tests/features/semantic_search.feature` (story 13): a meaning search finds a paper sharing no words with the query, hybrid merges both, fallback when Voyage is down.
- `tests/spec/features/semantic_search_spec.rb`: the same through Capybara, plus mode kept on sort/back, table-missing fallback, long-query cut.
- `tests/spec/models/paper_semantic_spec.rb`: ordering, papers with no embedding, `ranked_page`, sorts, hybrid, embedding text.
- `tests/spec/models/voyage_client_spec.rb`: request shape, retries, errors.

```sh
RAILS_ENV=test bundle exec rspec
RAILS_ENV=test bundle exec cucumber
```

## Known limits

- Semantic mode always returns 200 papers, even for a nonsense query; there is no relevance cutoff.
- Hybrid caps keyword matches at 200, so a broad query shows at most 200 results in Both but "1000+" in Keyword.
- `semantic_ids` searches all papers; it does not apply the year or area filters (the topic rankings do).
- `semantic_ids` returns ids only, not distances (`TopicRanking` selects its own distances).
- The query cache is `:memory_store` (32 MB) and is lost each time the Eco dyno sleeps.
- After the fallback the mode switches to Keyword, so the next page or sort stays on keyword.
- Some papers are stored twice under different ids and can both appear in results; some have scraped full text or no abstract, which hurts their embedding.

## Semantic ranking (topic rankings)

A search in Meaning or Both mode now also ranks universities **for that topic**: the rankings list is headed "Rankings for “query”". Keyword mode and the plain rankings page are unchanged. The work is in `app/models/topic_ranking.rb` (`TopicRanking < Ranking`).

**Which papers count.** The same papers as the plain ranking (conference papers and articles, selected years, venues of the selected areas), so the year and area filters apply. From those, the `POOL = 500` nearest to the query are taken. Only papers within `BAND = 0.08` cosine similarity below the `ANCHOR = 10`th best match are kept. The cutoff is relative because similarity values differ between queries. It is measured from the 10th match, not the 1st, so one near-duplicate of the query can't shrink it. On the 52-school data this keeps about 100–450 papers per topic.

**Score.** Each kept paper is worth a relevance weight: 1 at or above the anchor, falling to 0 at the edge of the band. The weight is split equally among its roster-faculty authors, the same split as the plain ranking's 1 point. A university's score is the sum of its professors' shares, so a paper shared inside one university is never counted twice. Rank numbering and the institution sort work as before.

**Faculty and professor pages.** "Show faculty" lists professors with topic papers, strongest first, with their topic score. "View papers" (which carries `q` and `mode`) shows that professor's topic papers, most relevant first.

**Cost and fallback.** One Voyage call per request: the controller fetches the query vector once (`Paper.query_vector`) and passes it to `semantic_ids` / `hybrid_ids` (new optional `vector:` keyword) and to `TopicRanking`. The vector search is an exact scan of the qualifying papers, forced with `ORDER BY (distance) + 0`, because the HNSW index would search all papers before filtering. It takes about 0.7–0.9 s on the 52-school data. If Voyage or the embeddings table fails, the page shows the plain ranking with the existing "unavailable" notice.

**Checked on real data** (query vectors averaged from on-topic papers, since a Voyage key wasn't available): "robot manipulation" puts CMU, UW, Stanford, MIT and Berkeley on top (Kroemer, Fox, Bohg, Tedrake, Abbeel); "differential privacy" puts UVA, Cornell, Penn State, Harvard and BU on top (Wang, Hsu, Kifer, Vadhan, Smith); "query optimization" puts Penn, Cornell, USC and MIT on top (Marcus, Trummer, Sabek, Kraska). `BAND` should be re-checked with a few real typed queries.

**Tests.** `tests/spec/models/topic_ranking_spec.rb` (scoring, band and anchor, author split, filters, missing embeddings, faculty and paper order, sort) and `tests/features/semantic_ranking.feature` (story 14).

**Not done.** Recency, venue tier and author position are not used in the score. The ranking isn't cached per query and filter set, so each page view recomputes it.
