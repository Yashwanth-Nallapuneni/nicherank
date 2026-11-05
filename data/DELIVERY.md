# Latest delivery and rebuild

Main and dev are loaded. Yashwanth does not need to import CSVs. Existing schema field names are unchanged. Both branches have pgvector 0.8.0 enabled; no embeddings or vector indexes were created.

The latest private bundle is `NicheRank_Tier_Vector_Delivery_2026-11-04.zip`. It includes `database/NicheRank_2026-11-04_tiers_vector_pg17.dump`, its SHA-256 manifest, the full `dataset/`, code, schema and QA. Locally the dump also resides under repository `data/delivery/`. Dumps, bulk exports, caches and credentials are intentionally ignored by Git. Share the bundle privately in addition to the Git push.

Tracked delivery files under repository `data/`:

- `SCHEMA.md` and `db/postgres/schema.sql`: authoritative contract and creation SQL.
- `reports/qa_main.json`, `reports/qa_dev.json`: final live QA.
- `reports/dump_verification.json`: archive hash and fresh Postgres 17 restore verification.
- `reports/venues/fresh_restore_qa.json`: full QA of the restored archive.
- `reports/venues/fresh_rebuild_qa.json`: full QA of a separate empty database rebuilt from CSV.
- `reports/venues/TIER_COVERAGE.md`: coverage, policy and remaining unknowns.

## Rebuild from the delivered snapshot

Prerequisites: Ruby dependencies from this package's Gemfile, PostgreSQL 17 with pgvector 0.8.0 available, a dedicated empty database and an owner connection allowed to create the extension. Store `DATABASE_URL=...` in a private chmod-600 file outside Git. From repository `data/` (or the unpacked `NicheRank_data/` root):

```sh
bundle install
ruby script/data/rebuild_postgres.rb /absolute/path/to/dataset /private/path/owner.env /absolute/path/to/rebuild_qa.json
```

This validates the snapshot, creates the schema and extension, loads all tables and runs structural/coverage/search QA. It refuses to erase existing rows. It makes no source API calls and needs no OpenAlex key. It does not stamp Rails migrations. Roles/connection passwords are not included in the dump or rebuild; provision read-only access separately when restoring elsewhere.

To reproduce both local verification paths (requires local PG17 binaries and pgvector installed):

```sh
ruby script/data/verify_dump_restore.rb /absolute/path/database/NicheRank_2026-11-04_tiers_vector_pg17.dump --verify-rebuild /absolute/path/dataset
```

The helper uses temporary databases on a Unix socket, checks the restored archive and a separate snapshot rebuild, and stops/removes its temporary server. The companion `.dump.manifest.json` must accompany the dump. Live review rows include historical decisions; a fresh CSV rebuild contains only the current review export. This expected difference does not affect the four core entity/link counts.

## Optional fields

`professors.rank` and `papers.venue_short` were not added. Rank needs a defined meaning (academic title versus query-dependent ranking); existing `professors.title` and full `papers.venue` remain available. No optional field blocks API integration.
