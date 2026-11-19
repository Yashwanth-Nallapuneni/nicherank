-- Additive, idempotent: venue quality labels kept separate from papers.venue_tier.
-- Join on exact venue name: papers.venue = venue_rankings.venue.
-- Apply only after a backup (pg_dump -Fc) and after telling the team.
CREATE TABLE IF NOT EXISTS venue_rankings (
  id           bigserial PRIMARY KEY,
  venue        text NOT NULL,
  kind         text NOT NULL CHECK (kind IN ('conference', 'journal')),
  source       text NOT NULL,   -- icore2026 | era2010 (later: scimago)
  source_id    text,            -- CORE portal entry id of the matched list row
  ranking      text NOT NULL,   -- A*/A/B/C for CORE sources (Q1 for scimago)
  match_method text NOT NULL,   -- exact_title | exact_acronym | parenthesized_acronym | issn | issn+title
  notes        text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (venue, source)
);
CREATE INDEX IF NOT EXISTS index_venue_rankings_on_venue ON venue_rankings (venue);
