> Historical sample/preparation notes. Superseded by `../HANDOFF_FOR_YASHWANTH.md`, `../SCHEMA.md`, and `../QA.md`.

# Handoff to Yashwanth / Claude

**Update:** A hosted Neon sample database is now live. See `NicheRank_Database_for_Yashwanth.md` beside the workspace and `db/postgres/deployment.json`. The backend URL is stored separately in ignored `tmp/credentials/yashwanth-database.env`. This supersedes the earlier assumption that PostgreSQL had not been provisioned.

Prepared November 4, 2026. This is the data-side deliverable only. No message, upload, commit or PR has been sent.

## Ready to test now

Use the files directly inside `db/data/sample/`. They contain ten verified university rows, 20 Stanford professors, 43 real papers, 43 authorships, two verified aliases, an empty duplicates table, and a review file. CSV headers and references pass local validation. The sample is intentionally a few recent papers per professor; it is not the full requested dataset.

Run your existing importer, adapting the absolute path:

```sh
bin/rails data:import DIR=/absolute/path/to/nicherank-data/db/data/sample
```

This command is from your supplied instructions. We have not executed or inspected the private importer; verify compatibility and tell us about any mismatch. You own PostgreSQL, migrations and the Rails importer.

## Important compatibility notes

1. OpenAlex now rejects `proceedings-article` as an API type filter. Collection uses `conference-paper`, and export maps that back to `proceedings-article` to preserve your agreed CSV contract. This is documented in the manifest.
2. The supported API page size is 100; the collector uses 100 rather than the deprecated 200.
3. Null optional fields are blank CSV cells; booleans are `true`/`false`. Unknown author positions remain blank.
4. Source author metrics cover their whole profile, whereas exported full-dataset publications will start in 2015.
5. Aliases join to the canonical professor ID. The sample includes real same-ORCID splits for Emma Brunskill and Leonidas Guibas.
6. The review file includes `faculty_eligibility` cases in addition to your suggested issue types; it is an audit file, not a new backend model requirement.
7. JMLR/TPAMI A* mappings are custom team policy. Do not present them as CORE journal ratings.
8. A `full` output directory name does not certify complete coverage. The collector keeps an explicit incomplete flag until the full matching/collection/QA pass has been reviewed.

## Repo integration after access

Copy/merge `script/data/`, `db/data/manual/`, `db/data/sample/`, the data docs and standalone tests into the existing Rails repository. **Do not replace your backend Gemfile or Rails application.** The OpenAlex collector needs no added gems; public HTML parsing needs Nokogiri. The small standalone Gemfile in this workspace only describes local preparation dependencies.

Ignore `tmp/openalex_cache/`, `tmp/public_sources/`, full outputs, secrets and ZIPs. Keep the real sample and small manual mapping/evidence files in Git, as agreed. Keep source snapshots outside Git but retain the raw-source archive so public preparation can be reproduced offline.

## What remains

- OpenAlex key: matching/alias review for the remaining roster, full cursor-based collection since 2015, full deduplication and high-frequency venue checks.
- Repo access: run the real importer and reconcile any schema/CSV differences.
- Your review: 25 ambiguous CMU appointments and three possible split-author cases. We have not silently guessed these identities/roles. The sample exporter also flags one possible paper duplicate.
- Final dataset: required ten-per-school spot checks, three known-professor checks, count/abstract/provenance review, final ZIP and agreed Drive upload.

Please test the sample while full collection is being prepared. The source data and code can proceed independently of database setup.
