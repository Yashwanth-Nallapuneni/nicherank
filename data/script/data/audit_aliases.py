#!/usr/bin/env python3
"""Recheck aliases using coauthor IDs, excluding every self-profile ID."""
import csv,json,collections
from pathlib import Path
root=Path(__file__).resolve().parents[2]
def read(p):return list(csv.DictReader(open(root/p,encoding='utf-8-sig')))
people={r['openalex_id']:r for r in read('db/data/manual/accepted_author_matches.csv')};aliases=read('db/data/manual/accepted_author_aliases.csv')
selfids={id:{id} for id in people}
for r in aliases:selfids[r['professor_openalex_id']].add(r['alias_openalex_id'])
targets=set().union(*selfids.values());co=collections.defaultdict(set);titles=collections.defaultdict(dict);count=0
for path in (root/'tmp/openalex_cache').glob('*.json'):
 with path.open() as f:
  prefix=f.read(1000)
  if '"endpoint": "works"' not in prefix:continue
  f.seek(0);j=json.load(f)
 for w in j.get('response',{}).get('results',[]):
  authorids={a.get('author',{}).get('id','').split('/')[-1] for a in w.get('authorships',[]) if a.get('author',{}).get('id')}
  for aid in authorids & targets:
   co[aid].update(authorids);titles[aid][w.get('id')]=w.get('title')
 count+=1
 if count%200==0:print('Read raw work pages:',count,flush=True)
rows=[]
for r in aliases:
 c,a=r['professor_openalex_id'],r['alias_openalex_id'];shared=(co[c]&co[a])-selfids[c]
 meta_c=json.loads((root/f'tmp/author_metadata/{c}.json').read_text())['author'];meta_a=json.loads((root/f'tmp/author_metadata/{a}.json').read_text())['author']
 same=bool(meta_c.get('orcid') and meta_c.get('orcid')==meta_a.get('orcid'))
 row={**r,'name':people[c]['name'],'same_primary_orcid':same,'shared_other_coauthor_ids':sorted(shared),'shared_other_coauthor_count':len(shared),'canonical_sample_works':list(titles[c])[:5],'alias_sample_works':list(titles[a])[:5],'status':'strong_id_evidence' if same and len(shared)>=2 else 'needs_additional_review'}
 rows.append(row)
(root/'reports/audit/alias_recheck.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2));print(collections.Counter(r['status'] for r in rows))
