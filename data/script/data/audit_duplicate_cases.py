#!/usr/bin/env python3
import csv,json,re,unicodedata,collections
from pathlib import Path
root=Path(__file__).resolve().parents[2]
def read(p):return list(csv.DictReader(open(root/p,encoding='utf-8-sig',newline='')))
def norm(s):return re.sub(r'\s+',' ',re.sub(r'[^\w\s]','',unicodedata.normalize('NFKC',s or '').lower())).strip()
works=json.loads((root/'tmp/audit/raw_work_index.json').read_text());review=read('data/output/full/review.csv');duplicates=read('data/output/full/duplicates.csv');papers={p['openalex_id']:p for p in read('data/output/full/papers.csv')};prof={r['openalex_id']:r for r in read('data/output/full/professors.csv')}
links=collections.defaultdict(set)
for r in read('data/output/full/authorships.csv'):links[r['paper_openalex_id']].add(r['professor_openalex_id'])
redirect={r['discarded_openalex_id']:r['retained_openalex_id'] for r in duplicates}
canonical={id:id for id in prof}
canonical.update({r['alias_openalex_id']:r['professor_openalex_id'] for r in read('db/data/manual/accepted_author_aliases.csv')})
policies={r['professor_openalex_id'] for r in read('db/data/manual/author_curation_policy.csv')}
support={(r['professor_openalex_id'],r['paper_openalex_id']) for r in read('db/data/manual/paper_attribution_reviews.csv') if r['decision']=='supported'}
selected=collections.defaultdict(set)
for wid,w in works.items():
 for aid in w['authors']:
  target=canonical.get(aid)
  if target and (target not in policies or (target,wid) in support):selected[wid].add(target)
for r in read('db/data/manual/paper_identity_overrides.csv'):selected[r['paper_openalex_id']].add(r['professor_openalex_id'])
generic={'introduction','editorial','preface','foreword','demo','demonstration','acknowledgments','acknowledgements','contents','table of contents','abstract','abstracts','index','book review','reviews','correction','erratum','the presidents page','einführung','invited article foreword'}
series={norm(r['venue']) for r in read('db/data/manual/venue_tiers.csv')}
rows=[]
for r in review:
 if r['issue_type']!='possible_duplicate':continue
 ids=re.findall(r'W\d+',r['candidate_ids']);pair=[works.get(w) for w in ids]
 if len(ids)!=2 or not all(pair):classification='insufficient_source_metadata'
 elif norm(pair[0]['title']) in generic or norm(pair[0]['title']) in series:classification='keep_separate_generic_or_series_title'
 elif abs((pair[0]['year'] or 0)-(pair[1]['year'] or 0))>1:classification='keep_separate_outside_year_rule'
 elif all(w.get('doi') for w in pair) and pair[0]['doi']!=pair[1]['doi']:classification='keep_separate_unverified_distinct_formal_dois'
 else:classification='keep_separate_no_supported_shared_author_merge'
 retained=[redirect.get(w,w) for w in ids];both=all(w in papers for w in retained);sameprof=bool(len(retained)==2 and links[retained[0]]&links[retained[1]])
 schools=[{prof[p]['university_openalex_id'] for p in links[w]} for w in retained]
 same_school=bool(len(schools)==2 and schools[0]&schools[1])
 rows.append({'title':r['name_or_venue'],'candidate_ids':r['candidate_ids'],'decision':classification,'both_records_in_current_export':both,'shared_selected_professor':sameprof,'shared_school':same_school,'status':'reviewed_keep_separate','reason':'No extra merge applied without adequate same-publication evidence; generic labels and distinct years are not identity keys'})
with open(root/'reports/audit/duplicate_case_review.csv','w',newline='') as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
# Recheck every merge in the corrected export against its recorded criterion.
checks=collections.Counter();fail=[]
for r in duplicates:
 a,b=works[r['discarded_openalex_id']],works[r['retained_openalex_id']]
 da=(a.get('doi') or '').lower().replace('https://doi.org/','');db=(b.get('doi') or '').lower().replace('https://doi.org/','')
 if r['reason']=='doi':ok=bool(da and da==db);checks['exact_doi_merges']+=1
 else:
  ok=norm(a['title'])==norm(b['title']) and abs(a['year']-b['year'])<=1 and norm(a['title']) not in generic and norm(a['title']) not in series and bool(selected[a['id']] & selected[b['id']])
  checks['descriptive_title_year_merges']+=1
  preprint=any(x.get('type')=='preprint' or any(s in (x.get('doi') or '') for s in ['10.48550/','10.1101/','10.2139/']) for x in [a,b])
  if preprint:checks['title_merges_with_preprint_identifier_or_type']+=1
  elif da and db and da!=db:
   checks['different_formal_dois_not_permitted']+=1
   ok=False
 if not ok:fail.append(r)
summary={'current_dedup_decisions_rechecked':len(duplicates),'merge_rule_failures':len(fail),'merge_categories':dict(checks),'collision_cases_reviewed':len(rows),'collision_decisions':dict(collections.Counter(r['decision'] for r in rows)),'collision_pairs_with_shared_selected_professor':sum(r['shared_selected_professor'] for r in rows),'collision_pairs_with_shared_school':sum(r['shared_school'] for r in rows),'restored_previously_collapsed_records':len(json.loads((root/'reports/audit/restored_prior_duplicate_ids.json').read_text())),'limitation':'Different formal DOIs remain separate without verified version evidence. Descriptive title/year/shared-author merging still covers missing-DOI and recognizable preprint cases; this remains a heuristic. Ambiguous cases are not certified distinct.'}
(root/'reports/audit/duplicate_audit_summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
if fail:
 print(json.dumps(fail,indent=2))
 raise RuntimeError('A merge fails the corrected policy')
