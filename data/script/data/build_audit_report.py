#!/usr/bin/env python3
"""Create a reproducible, qualified audit report from the recorded evidence."""
import csv,json,collections,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=root/'reports/audit'
def read(p):return list(csv.DictReader(open(root/p,encoding='utf-8-sig',newline='')))
a=json.loads((out/'author_audit_summary.json').read_text());r=json.loads((out/'revision_decisions.json').read_text());d=json.loads((out/'duplicate_audit_summary.json').read_text());m=json.loads((root/'data/output/full/manifest.json').read_text());decisions=read('db/data/manual/paper_attribution_reviews.csv')
source_manifest=[]
for folder in ['sources','manual_sources','crossref']:
 for path in (root/f'tmp/audit/{folder}').glob('*.json'):
  j=json.loads(path.read_text());source_manifest.append({k:j[k] for k in ['url','doi','final_url','status','retrieved_at','sha256'] if k in j})
(out/'source_manifest.json').write_text(json.dumps(source_manifest,ensure_ascii=False,indent=2))
remaining='\n'.join('- '+x for x in r['remaining_unresolved'])
policies='\n'.join('- '+x for x in r['curated_professors'])
new='\n'.join('- '+x for x in r['resolved_previously_missing'])
corrections='\n'.join(f"| {x['name']} | `{x['old_openalex_id']}` | `{x['new_openalex_id']}` |" for x in r['canonical_corrections'])
current_aliases=read('db/data/manual/accepted_author_aliases.csv');current={(x['professor_openalex_id'],x['alias_openalex_id']) for x in current_aliases};baseline_alias=json.loads((out/'alias_recheck.json').read_text())
strong_kept=sum(x['status']=='strong_id_evidence' and (x['professor_openalex_id'],x['alias_openalex_id']) in current for x in baseline_alias)
old_alias=set((x['professor_openalex_id'],x['alias_openalex_id']) for x in read('tmp/audit/baseline_v1/accepted_author_aliases.csv'))
manual_new=sum((x['professor_openalex_id'],x['alias_openalex_id']) not in old_alias for x in current_aliases)
report=f'''# NicheRank author, coverage, alias and duplicate audit

Audit revision 2; source cutoff **2026-11-04 (America/New_York)**. This audit supersedes the first data delivery. It includes actual corrections, not only database constraint checks.

## Outcome

Current export: **{m['counts']['professors']:,} professors, {m['counts']['papers']:,} papers, {m['counts']['authorships']:,} authorships and {m['counts']['author_aliases']} aliases across 10 schools**. Three eligible roster identities remain unresolved. No per-person collection cap was introduced; verification-based withholding is explicitly documented for high-risk mixed profiles.

## 1. Author accuracy

Every one of the **1,116 baseline profiles** received a local screen. **3,316 professor–paper sample pairs** were selected, favoring high-citation, newest and oldest records. Source-ID/name agreement was checked; this is internal consistency, not independent verification.

Faculty-linked public pages independently corroborated samples for **400 baseline professors** (721 professor–paper pairs). A second pass checked publisher-deposited Crossref DOI records for the remaining eligible samples. It required matching names plus an ORCID or current-institution match; name-only matches were inconclusive. This corroborated **331 additional baseline professors**, making **731 baseline professors with at least one independently corroborated paper sample**. New and corrected identities have separate manual evidence.

**This does not certify every paper or all 1,116 identities.** Of the remaining baseline rows, 263 have inconclusive independent sample evidence, 116 have consistent independent identifier hints but no corroborated sample, two had zero papers requiring investigation, and four were corrected as described below. Inaccessible pages, incomplete publication lists and missing publisher affiliations/ORCIDs are not treated as proof of error. Automated corroboration is not described as individual human review.

Four canonical profile selections were corrected:

| Faculty | Prior profile | Corrected profile |
|---|---|---|
{corrections}

Tom Costello's CMU faculty page identifies a psychologist; the earlier logic-researcher match was wrong. Berkeley's John Wright works in quantum theory; the earlier hardware-design profile was wrong. Georgia Tech's Xiuwei Zhang works in computational genomics; the earlier remote-sensing profile was wrong. Kozyrakis required the published-name form Christos rather than only the older Christoforos profile.

Eleven high-risk identities now use independently supported paper-level curation:

{policies}

`paper_attribution_reviews.csv` records **{sum(x['decision']=='supported' for x in decisions)} supported candidate attributions** and **{sum(x['decision']=='withhold' for x in decisions)} withheld candidate attributions**. These are source-profile/paper decisions, not a global paper count. Withheld means insufficient independent support on the checked pages, **not a declaration that the work is false**. This deliberately sacrifices some recall instead of importing demonstrably mixed profiles wholesale. Fifteen Wei Hu records use explicit paper-level reassignment from a mixed source ID, rather than a whole-profile alias.

Career work counts, h-index and first-publication year are SQL NULL for curated mixed profiles when person-level values cannot safely be established. Their paper links remain usable for keyword search. See `professor_metric_overrides.csv`.

## 2. Coverage investigation

Ten of the previously missing identities now have independently supported matches:

{new}

The roster contains 1,130 source entries; one deceased memorial entry is excluded, leaving 1,129 eligible entries. The revised export contains 1,126, with these three still unresolved:

{remaining}

All three were investigated using official faculty information and name/profile/publication evidence. Paulisick's CMU entrepreneurship/AI teaching role and Pinto da Silva's Design/HCII identity were established, but a reliable OpenAlex person ID was not. Furst's mathematics identity was established; a similarly named/mixed dentistry profile was not accepted as a complete current bibliography. They are not silently classified as ineligible or as having no publications. The schema requires a unique non-NULL OpenAlex author ID, so guessed rows were not created.

The separate 25 unresolved CMU eligibility cases remain omitted as previously agreed.

Of the original four zero-paper faculty, Tom Costello and Kozyrakis were fixed by correcting the canonical profile; Dimitrios Apostolopoulos gained three faculty-page-supported papers through the Dimi name variant. Ari Lightman remains a legitimate matched roster entry with zero qualifying papers in the checked source collection. This does not establish that he has no publications outside the indexed scope.

## 3. Aliases and duplicates

Every original alias was rechecked using **other coauthor IDs**, excluding all self-profile IDs. Ninety original aliases met the stronger same-primary-ORCID plus two-other-coauthor-ID rule. Seven did not meet that rule; four of those had independent faculty-publication evidence and were retained, while three were withheld. One further alias belonged to the wrong Xiuwei Zhang identity and was removed with that correction. The revised 101 aliases consist of **{strong_kept} retained strong-ID cases, four independently corroborated exceptions, and {manual_new} explicit manually evidenced additions**.

No uncertain Barrett/Goodman/Wu aliases were added. Differing ORCIDs were not merged merely because names or topics matched. Manual additions are supported by faculty-listed publications/name variants, with per-paper restrictions for mixed profiles. CSRankings hints contained 19 identifier discrepancies; they were treated as review signals, not automatic truth. For example, the Pfenning semiconductor, O'Donnell radar, Valiant sibling and Horowitz psychiatry hints were not used to overwrite supported faculty identities.

Duplicate handling is stricter:

- Exact normalized DOI matches still merge.
- Generic or series titles such as Introduction, Demo, Editorial and annual conference-volume names no longer merge on title/year/author alone.
- **Distinct formal publication DOIs remain separate** without verified version evidence. A matching title is not enough to collapse two formally identified publications.
- Descriptive title/year/shared-author matching remains for missing-DOI or recognizable preprint cases. This is explicitly a heuristic, not a universal identity guarantee.

All **{d['current_dedup_decisions_rechecked']:,} current merge decisions** were rechecked against the recorded criteria; failures: **{d['merge_rule_failures']}**. There are **{d['merge_categories'].get('exact_doi_merges',0)} exact-DOI merges** and **{d['merge_categories'].get('descriptive_title_year_merges',0)} descriptive-title/year merges**, of which {d['merge_categories'].get('title_merges_with_preprint_identifier_or_type',0)} have a recognizable preprint identifier or type.

All **{d['collision_cases_reviewed']:,} remaining collision-pair cases** were classified and kept separate under the conservative policy. This is a review decision, not proof that every pair represents different underlying research. Counts by decision are in `duplicate_audit_summary.json`; pair-level decisions are in `duplicate_case_review.csv`. Some genuine conference/journal versions may remain separate until publisher relationships can be established.

The generic-title pass alone recovered 61 previously discarded records; the final stricter formal-DOI policy recovers additional separately identified records. The final restored-ID list is in `restored_prior_duplicate_ids.json`.

## Validation and remaining limits

The reconciliation workflow was exercised on a fresh local restore of v1, then repeated. It retained professor numeric IDs, removed only superseded derived links, preserved review history, and a repeated load changed zero entity/link rows. Live main/dev QA and the final fresh dump-restore reports are delivered alongside this audit.

Known limits remain: incomplete source coverage for three identities; some uncorroborated samples; partial bibliographies for curated mixed profiles; unresolved alias candidates; and conservative duplicate handling that can retain distinct formal versions. **Dataset completeness remains false.** The audit materially improves the data but does not claim universal authorship accuracy.

## Evidence files and attribution

- `author_audit_results.csv`, `author_audit_summary.json`: one result per baseline faculty member.
- `independent_sample_evidence*.json`: exact faculty-page title/DOI evidence.
- `publisher_sample_evidence.json`: publisher author/ORCID/affiliation evidence; name-only cases remain inconclusive.
- `reference_hints.csv`: CSRankings homepage/ORCID hints, [upstream source](https://github.com/emeryberger/CSrankings/blob/gh-pages/csrankings.csv). These facts were used for cross-checking; no CSRankings application code was copied.
- `alias_recheck.json`, `alias_exceptions.json`, `curation_candidates.json`, `revision_decisions.json`: alias and identity decisions.
- `source_manifest.json`: retrieval metadata/hashes; raw page/API caches stay out of Git.
- [Crossref REST API](https://www.crossref.org/documentation/retrieve-metadata/rest-api/): publisher-deposited metadata used for DOI checks; abstract text was not copied into the audit cache.
- `db/data/manual/identity_corrections.csv`, `author_curation_policy.csv`, `paper_attribution_reviews.csv`, `paper_identity_overrides.csv`: the machine-readable correction inputs.
'''
(out/'AUDIT_REPORT.md').write_text(report)
print('Built qualified audit report and source manifest.')
