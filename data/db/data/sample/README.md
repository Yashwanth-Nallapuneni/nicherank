# Real NicheRank import sample

Collected November 4, 2026 through OpenAlex public key-free lookups and official faculty sources.

**Sample only:** 20 Stanford professors; at most two recent qualifying works per canonical/verified alias profile. The ten university rows supply verified institution metadata. This is not the full dataset.

- universities: 10
- professors: 20
- papers: 43
- authorships: 43
- author_aliases: 2
- duplicates: 0
- review: 29

Abstract coverage: 97.67%.

Conference papers are exported as `proceedings-article` to retain the agreed CSV contract; OpenAlex now calls them `conference-paper`. Journal tiers are custom team policy, not CORE conference ranks.

See manifest.json for source timestamps and limitations, review.csv for uncertainties, and db/data/manual/author_match_checks.csv in the collector workspace for identity evidence.

Expected backend import command (provided by Yashwanth; not run here):

```sh
bin/rails data:import DIR=/absolute/path/to/this/sample
```
