#!/usr/bin/env python3
"""Apply explicit, independently evidenced audit decisions to local inputs.
No database access. Preserve the v1 export for rollback and comparison.
"""
import csv,json,shutil,collections
from pathlib import Path
root=Path(__file__).resolve().parents[2];manual=root/'db/data/manual';baseline=root/'tmp/audit/baseline_v1';baseline.mkdir(parents=True,exist_ok=True)
def read(p):return list(csv.DictReader(open(p,encoding='utf-8-sig',newline='')))
def write(p,rows,headers=None):
 with open(p,'w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=headers or list(rows[0]));w.writeheader();w.writerows(rows)
for file in ['accepted_author_matches.csv','accepted_author_aliases.csv','identity_review_remaining.csv','identity_overrides.csv']:
 if not (baseline/file).exists():shutil.copy2(manual/file,baseline/file)
if not (baseline/'export').exists():shutil.copytree(root/'data/output/full',baseline/'export')
old=read(baseline/'accepted_author_matches.csv');byname={r['name']:r for r in old};roster={r['name']:r for r in read(manual/'faculty_raw.csv')}
changes={
'Tom Costello':('A5055631608','https://www.hcii.cmu.edu/people/tom-costello','Psychology identity verified on CMU faculty page and Science AI-dialogue publication; replaces logic namesake'),
'Christoforos Kozyrakis':('A5042148531','https://mast.stanford.edu/pubs','Published name Christos Kozyrakis; 116 raw work IDs corroborated on faculty-linked lab publication page'),
'Xiuwei Zhang':('A5087386964','https://xiuweizhang.wordpress.com/publications/','Computational single-cell genomics identity; replaces remote-sensing namesake; title-level curation applied'),
'John Wright':('A5144385508','https://people.eecs.berkeley.edu/~jswright/','Quantum theory faculty identity; replaces hardware-design namesake; corroborated quantum publications'),
'Michael Kim':('A5128273496','https://www.cs.cornell.edu/~mpkim/pubs.html','Published name Michael P Kim; current omniprediction papers corroborated; source-supported split records curated'),
'Qi Tang':('A5036456769','https://tangqi.github.io/publications/','Computational plasma physics faculty; unrelated battery/materials records on mixed profile withheld'),
'Steve Mussmann':('A5034715099','https://proceedings.mlr.press/v119/koh20a.html','Published name Stephen Mussmann; ICML Concept Bottleneck Models and faculty biography distinguish genetics namesake'),
'Will Perkins':('A5010848870','https://willperkins.org/','Combinatorics and probability faculty; 58 work IDs corroborated on own page; mixed career metrics withheld'),
'Yiying Zhang':('A5100741029','https://cseweb.ucsd.edu/~yiying/publication.html','Systems faculty verified through LegoOS and full publication list; unsupported mixed-profile records withheld'),
'Bo Li':('A5100677409','https://aisecure.github.io/PUBLICATIONS/index.html','UIUC trustworthy ML faculty; distinct published-name/ORCID splits supported by own publication list and curated per work'),
'Gang Wang':('A5100367418','https://gangw.cs.illinois.edu/','UIUC security faculty; 27 work IDs independently corroborated; materials/control namesakes rejected'),
'Hao Peng':('A5101460572','https://haopeng-nlp.github.io/publications/','UIUC NLP faculty; independently listed publications identify the correct splits; unsupported records withheld'),
'Ryan Huang':('A5078778324','https://web.eecs.umich.edu/~ryanph/','Published name Peng Huang; systems publications and faculty biography; oncology namesake rejected'),
'Wei Hu':('A5153519514','https://weihu.me/','Michigan learning-theory faculty; canonical current profile plus individually verified papers from a mixed source ID; no whole-profile merge')}
corrections=[]
for name,(aid,url,reason) in changes.items():
 oldrow=byname.get(name);person=roster[name]
 if oldrow and oldrow['openalex_id']!=aid:corrections.append({'name':name,'old_openalex_id':oldrow['openalex_id'],'new_openalex_id':aid,'evidence_url':url,'reason':reason})
 byname[name]={'university':person['university'],'name':name,'openalex_id':aid,'match_confidence':'manual','status':'verified','evidence_url':url+'; https://openalex.org/'+aid,'alias_checked_on':'2026-11-04','notes':'Audit revision 2: '+reason}
accepted=sorted(byname.values(),key=lambda r:(r['university'],r['name']))
write(manual/'accepted_author_matches.csv',accepted,list(old[0]));write(manual/'identity_corrections.csv',corrections)
# Keep the repeatable identity-review stage consistent with the audited choices.
overrides={r['name']:r for r in read(baseline/'identity_overrides.csv')}
for name,(aid,url,reason) in changes.items():overrides[name]={'name':name,'openalex_id':aid,'reason':'Audit revision 2: '+reason}
write(manual/'identity_overrides.csv',list(overrides.values()))
remaining=[r for r in read(baseline/'identity_review_remaining.csv') if r['name_or_venue'] not in changes]
write(manual/'identity_review_remaining.csv',remaining,list(read(baseline/'identity_review_remaining.csv')[0]))
# Revoke the three earlier aliases lacking independent-ID or publication evidence.
withheld={'A5102953466','A5124151175','A5138274163'}
accepted_ids={r['openalex_id'] for r in accepted}
withheld.update(r['alias_openalex_id'] for r in read(baseline/'accepted_author_aliases.csv') if r['professor_openalex_id'] not in accepted_ids)
aliases=[r for r in read(baseline/'accepted_author_aliases.csv') if r['alias_openalex_id'] not in withheld]
# Explicit manual split evidence; mixed candidates are restricted per paper below.
extras={'A5042148531':['A5072960733'],'A5103559261':['A5030375154'],'A5144385508':['A5102755411'],'A5100762970':['A5026118558'],'A5100677409':['A5127811360'],'A5128273496':['A5107234230'],'A5101460572':['A5153970819','A5137004474']}
for canonical,ids in extras.items():
 for aid in ids:aliases.append({'professor_openalex_id':canonical,'alias_openalex_id':aid})
write(manual/'accepted_author_aliases.csv',aliases,['professor_openalex_id','alias_openalex_id'])
# Known mixed profiles are deliberately scoped by independently supported paper IDs.
policies={'Xiuwei Zhang','Lin Ma','Jason Li','Qi Tang','Yiying Zhang','Bo Li','Hao Peng','Ryan Huang','Wei Hu','Will Perkins','Michael Kim'}
write(manual/'author_curation_policy.csv',[{'professor_openalex_id':byname[n]['openalex_id'],'name':n,'policy':'require_independent_publication_evidence','reason':'Mixed source profile or high-risk split; unmatched records withheld without asserting they are incorrect'} for n in sorted(policies)])
proposals=json.loads((root/'reports/audit/curation_candidates.json').read_text());decisions=[];paper_overrides=[]
works=json.loads((root/'tmp/audit/raw_work_index.json').read_text())
for proposal in proposals:
 n=proposal['name'];aid=proposal['candidate_id']
 if n not in policies:continue
 canonical=byname[n]['openalex_id'];support={r['work_id']:r for r in proposal['supported_records']}
 eligible_ids={canonical}|set(extras.get(canonical,[]))
 if aid not in eligible_ids and not (n=='Wei Hu' and aid=='A5100727084'):continue
 for wid,w in works.items():
  if aid not in w['authors']:continue
  proof=support.get(wid)
  decisions.append({'professor_openalex_id':canonical,'source_author_openalex_id':aid,'paper_openalex_id':wid,'decision':'supported' if proof else 'withhold','evidence_url':proof['source_url'] if proof else '', 'reason':'Exact normalized publication title or DOI on faculty-linked publication page' if proof else 'No independent support in checked faculty publication pages; not declared a false publication'})
  if proof and aid not in eligible_ids:paper_overrides.append({'source_author_openalex_id':aid,'professor_openalex_id':canonical,'paper_openalex_id':wid,'evidence_url':proof['source_url'],'reason':'Paper-level attribution only; mixed source profile is not a whole-person alias'})
write(manual/'paper_attribution_reviews.csv',decisions)
write(manual/'paper_identity_overrides.csv',paper_overrides,['source_author_openalex_id','professor_openalex_id','paper_openalex_id','evidence_url','reason'])
# Mixed career metrics cannot honestly be presented as the person's metrics.
write(manual/'professor_metric_overrides.csv',[{'professor_openalex_id':byname[n]['openalex_id'],'first_pub_year':'NULL','works_count':'NULL','h_index':'NULL','reason':'Source profile/splits are mixed or incompletely resolved; unknown person-level career metrics remain NULL'} for n in sorted(policies)])
summary={'baseline_professors':len(old),'revised_professors':len(accepted),'canonical_corrections':corrections,'resolved_previously_missing':sorted(set(changes)-set(r['name'] for r in old)),'remaining_unresolved':[r['name_or_venue'] for r in remaining],'aliases_before':len(read(baseline/'accepted_author_aliases.csv')),'aliases_after':len(aliases),'withheld_alias_ids':sorted(withheld),'explicit_whole_profile_splits':extras,'curated_professors':sorted(policies),'supported_attributions':sum(r['decision']=='supported' for r in decisions),'withheld_attributions':sum(r['decision']=='withhold' for r in decisions),'paper_only_remaps':len(paper_overrides)}
(root/'reports/audit/revision_decisions.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
