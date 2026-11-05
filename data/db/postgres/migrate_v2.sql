-- Contract confirmed by the backend team. Run once, transactionally, after
-- testing on dev. Rows and relationships are retained; no table is dropped.
ALTER TABLE public.papers RENAME COLUMN type TO paper_type;
ALTER TABLE public.papers ADD COLUMN venue_tier_source text
  CHECK (venue_tier_source IN ('core2023','custom'));
ALTER TABLE public.papers DROP CONSTRAINT papers_type_check;
UPDATE public.papers SET paper_type='conference-paper'
  WHERE paper_type='proceedings-article';
ALTER TABLE public.papers ADD CONSTRAINT papers_paper_type_check
  CHECK (paper_type IN ('article','conference-paper','preprint','book-chapter'));
UPDATE public.papers SET venue_tier_source = CASE
  WHEN venue_tier IS NULL THEN NULL
  WHEN venue IN ('Journal of Machine Learning Research','JMLR',
    'IEEE Transactions on Pattern Analysis and Machine Intelligence','TPAMI') THEN 'custom'
  ELSE 'core2023' END;
ALTER TABLE public.papers ALTER COLUMN search_vector SET EXPRESSION AS (
  setweight(to_tsvector('english'::regconfig,coalesce(title,'')), 'A') ||
  setweight(to_tsvector('english'::regconfig,coalesce(keywords,'')), 'A') ||
  setweight(to_tsvector('english'::regconfig,coalesce(primary_topic,'')), 'B') ||
  setweight(to_tsvector('english'::regconfig,coalesce(abstract,'')), 'C')
);
UPDATE public.dataset_metadata SET manifest = manifest ||
  '{"database_schema_version":2,"database_paper_type":"conference-paper","search_weights":{"title":"A","keywords":"A","primary_topic":"B","abstract":"C"}}'::jsonb;
