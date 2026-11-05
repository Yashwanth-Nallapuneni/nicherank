#!/usr/bin/env python3
"""Screen every accepted identity and all prior deduplication decisions.
Source-ID consistency is a screen, not independent author verification.
"""
import csv,json,gzip,unicodedata,re,collections
from pathlib import Path
root=Path(__file__).resolve().parents[2]
def read(p):
 with open(root/p,newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))
def norm(s):return ''.join(c for c in unicodedata.normalize('NFKD',s or '').lower() if c.isalnum() or c.isspace()).strip()
def key(s):return re.sub(r'\s+',' ',norm(s))
def names(s):return re.findall(r'[a-z]+',unicodedata.normalize('NFKD',s or '').lower())
def compatible(a,b):
 a,b=names(a),names(b)
 if not a or not b:return False
 return ''.join(a)==''.join(b) or (a[-1]==b[-1] and a[0][0]==b[0][0])
people=read('db/data/manual/accepted_author_matches.csv'); aliases=read('db/data/manual/accepted_author_aliases.csv')
canon={r['openalex_id']:r['openalex_id'] for r in people};canon.update({r['alias_openalex_id']:r['professor_openalex_id'] for r in aliases})
byid={r['openalex_id']:r for r in people}; works={}
for path in sorted((root/'tmp/work_batches').glob('*.gz')):
 if not Path(str(path)+'.manifest.json').exists():continue
 with gzip.open(path,'rt') as f:
  for line in f:
   w=json.loads(line);id=w['id'].split('/')[-1]
   slim={'id':id,'title':w.get('title'),'year':w.get('publication_year'),'date':w.get('publication_date'),'doi':w.get('doi'),'type':w.get('type'),'citations':w.get('cited_by_count',0),'venue':((w.get('primary_location') or {}).get('source') or {}).get('display_name'),'topic':(w.get('primary_topic') or {}).get('display_name'),'field':((w.get('primary_topic') or {}).get('field') or {}).get('display_name')}
   slim['authors']={a.get('author',{}).get('id','').split('/')[-1]:a.get('author',{}).get('display_name') for a in w.get('authorships',[]) if a.get('author',{}).get('id')}
   if id in works:works[id]['authors'].update(slim['authors'])
   else:works[id]=slim
 print('Read batch; unique works:',len(works),flush=True)
(root/'tmp/audit/raw_work_index.json').write_text(json.dumps(works,ensure_ascii=False))
per=collections.defaultdict(list)
for w in works.values():
 for id,n in w['authors'].items():
  if id in canon:per[canon[id]].append(w)
rows=[]; samples=[]
for p in people:
 id=p['openalex_id'];meta=json.loads((root/f'tmp/author_metadata/{id}.json').read_text())['author'];ws=list({w['id']:w for w in per[id]}.values())
 variants=[p['name'],meta.get('display_name','')]
 mismatches=[]
 for w in ws:
  linked=[n for aid,n in w['authors'].items() if canon.get(aid)==id]
  if not any(compatible(n,v) for n in linked for v in variants):mismatches.append(w['id'])
 chosen=[]
 for sortkey,reverse in [(lambda w:w['citations'] or 0,True),(lambda w:w['date'] or '',True),(lambda w:w['date'] or '',False)]:
  for w in sorted(ws,key=sortkey,reverse=reverse):
   if w['id'] not in [x['id'] for x in chosen]:chosen.append(w);break
 for wid in mismatches[:2]:
  if wid not in [x['id'] for x in chosen]:chosen.append(works[wid])
 flags=[]
 if not ws:flags.append('zero_collected_papers')
 if mismatches:flags.append('paper_author_name_mismatch')
 if not compatible(p['name'],meta.get('display_name','')):flags.append('published_name_variant')
 row={**p,'source_display_name':meta.get('display_name'),'raw_linked_papers':len(ws),'name_mismatch_papers':len(mismatches),'flags':';'.join(flags),'audit_status':'needs_independent_evidence','sample_ids':';'.join(w['id'] for w in chosen)}
 rows.append(row);samples.append({'professor':row,'samples':chosen,'mismatch_ids':mismatches})
(root/'tmp/audit/author_samples.json').write_text(json.dumps(samples,ensure_ascii=False))
with open(root/'reports/audit/author_screen.csv','w',newline='') as f:
 wr=csv.DictWriter(f,fieldnames=list(rows[0]));wr.writeheader();wr.writerows(rows)
dups=read('data/output/full/duplicates.csv'); audited=[]
generic=re.compile(r'^(editorial|introduction|preface|foreword|acknowledg(e)?ments?|correction|erratum|contents|abstracts?|proceedings|index|book review|reviews?)$',re.I)
for r in dups:
 a=works.get(r['discarded_openalex_id']);b=works.get(r['retained_openalex_id'])
 if not a or not b:continue
 short=generic.fullmatch(key(a['title'])) is not None or len(key(a['title']).split())<4
 different_doi=bool(a['doi'] and b['doi'] and a['doi']!=b['doi'])
 risk=bool(r['reason']=='safe_title' and (short or (different_doi and a['venue'] and b['venue'] and a['venue']!=b['venue'])))
 audited.append({**r,'title':a['title'],'year_a':a['year'],'year_b':b['year'],'doi_a':a['doi'],'doi_b':b['doi'],'venue_a':a['venue'],'venue_b':b['venue'],'generic_or_short_title':short,'distinct_dois':different_doi,'requires_review':risk})
with open(root/'reports/audit/dedup_decisions.csv','w',newline='') as f:
 wr=csv.DictWriter(f,fieldnames=list(audited[0]));wr.writeheader();wr.writerows(audited)
summary={'professors_screened':len(rows),'professors_with_name_mismatch':sum(r['name_mismatch_papers']>0 for r in rows),'sampled_professor_paper_pairs':sum(len(s['samples']) for s in samples),'dedup_decisions_screened':len(audited),'dedup_decisions_flagged':sum(r['requires_review'] for r in audited),'independent_verification_complete':False}
(root/'reports/audit/local_screen_summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
