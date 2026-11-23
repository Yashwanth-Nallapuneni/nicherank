-- Semantic search: one Voyage embedding per paper (title + abstract).
-- Additive only: no existing table is changed. Safe to run more than once.
-- Rebuild for a paper by deleting its row and re-running `rake embeddings:backfill`.
CREATE EXTENSION IF NOT EXISTS vector;
CREATE TABLE IF NOT EXISTS public.paper_embeddings (
  paper_id bigint PRIMARY KEY REFERENCES public.papers(id) ON DELETE CASCADE,
  embedding vector(512) NOT NULL,
  model text NOT NULL,
  embedded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS index_paper_embeddings_on_embedding
  ON public.paper_embeddings USING hnsw (embedding vector_cosine_ops);
