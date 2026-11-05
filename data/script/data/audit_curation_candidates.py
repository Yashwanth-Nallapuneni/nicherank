#!/usr/bin/env python3
import json,gzip,csv,re,unicodedata,html,collections
from pathlib import Path
from html.parser import HTMLParser
root=Path(__file__).resolve().parents[2]
def norm(s):return re.sub(r'[^a-z0-9]','',unicodedata.normalize('NFKD',html.unescape(s or '')).lower())
class Text(HTMLParser):
 def __init__(self):super().__init__();self.parts=[]
 def handle_data(self,s):self.parts.append(s)
works=json.loads((root/'tmp/audit/raw_work_index.json').read_text())
for path in (root/'tmp/work_batches').glob('*.gz'):
 if not Path(str(path)+'.manifest.json').exists():continue
 with gzip.open(path,'rt') as f:
  for l in f:
   w=json.loads(l);id=w['id'].split('/')[-1];authors={a['author']['id'].split('/')[-1]:a['author'].get('display_name') for a in w.get('authorships',[]) if a.get('author',{}).get('id')}
   if id in works:works[id]['authors'].update(authors);continue
   works[id]={'id':id,'title':w.get('title'),'year':w.get('publication_year'),'date':w.get('publication_date'),'doi':w.get('doi'),'type':w.get('type'),'citations':w.get('cited_by_count',0),'venue':((w.get('primary_location') or {}).get('source') or {}).get('display_name'),'topic':(w.get('primary_topic') or {}).get('display_name'),'field':((w.get('primary_topic') or {}).get('field') or {}).get('display_name'),'authors':authors}
(root/'tmp/audit/raw_work_index.json').write_text(json.dumps(works,ensure_ascii=False))
sources=collections.defaultdict(list)
for p in (root/'tmp/audit/manual_sources').glob('*.json'):
 j=json.loads(p.read_text());t=Text();t.feed(j.get('raw',''));sources[j['name']].append((j.get('final_url',j['url']),norm(' '.join(t.parts)),norm(j.get('raw','')),j.get('raw','').lower()))
targets={'Tom Costello':['A5055631608'],'Christoforos Kozyrakis':['A5042148531','A5072960733'],'Xiuwei Zhang':['A5087386964'],'John Wright':['A5144385508','A5102755411'],'Lin Ma':['A5072023220'],'Jason Li':['A5100762970','A5026118558'],'Qi Tang':['A5036456769'],'Yiying Zhang':['A5100741029'],'Bo Li':['A5100677409','A5127811360','A5100374474'],'Gang Wang':['A5100367418','A5137384173'],'Ryan Huang':['A5078778324'],'Wei Hu':['A5100727084','A5153519514'],'Hao Peng':['A5153970819','A5137004474','A5101460572'],'Michael Kim':['A5107234230','A5128273496','A5141223098'],'Will Perkins':['A5010848870'],'Steve Mussmann':['A5034715099'],'Dimitrios S Apostolopoulos':['A5030375154','A5103559261']}
rows=[]
for name,ids in targets.items():
 for aid in ids:
  records=[w for w in works.values() if aid in w['authors']]
  hits=[]
  for w in records:
   title=norm(w.get('title'));doi=(w.get('doi') or '').replace('https://doi.org/','').lower();url=None
   for source,txt,raw,original in sources[name]:
    if (len(title)>=25 and (title in txt or title in raw)) or (doi and doi in original):url=source;break
   if url:hits.append({'work_id':w['id'],'title':w['title'],'source_url':url})
  rows.append({'name':name,'candidate_id':aid,'qualifying_raw_records':len(records),'supported_records':hits})
  print(name,aid,'source-supported',len(hits),'of',len(records),flush=True)
(root/'reports/audit/curation_candidates.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
# The original seven alias exceptions get an independent-publication check.
allpages={}
for folder in ['source_results','source_results_hints']:
 for p in (root/f'tmp/audit/{folder}').glob('*.json'):
  j=json.loads(p.read_text());allpages.setdefault(j['name'],set()).update(j['sources'])
cache={}
for p in (root/'tmp/audit/sources').glob('*.json'):
 j=json.loads(p.read_text());t=Text();t.feed(j.get('raw',''));cache[j.get('final_url',j['url'])]=(norm(' '.join(t.parts)),norm(j.get('raw','')))
exceptions=[]
for r in json.loads((root/'reports/audit/alias_recheck.json').read_text()):
 if r['status']=='strong_id_evidence':continue
 aid=r['alias_openalex_id'];hits=[]
 for w in works.values():
  if aid not in w['authors']:continue
  title=norm(w.get('title'))
  for url in allpages.get(r['name'],[]):
   txt,raw=cache.get(url,('',''))
   if len(title)>=25 and (title in txt or title in raw):hits.append({'work_id':w['id'],'title':w['title'],'source_url':url});break
 r['independent_paper_evidence']=hits;exceptions.append(r);print('ALIAS',r['name'],aid,'supported:',len(hits),flush=True)
(root/'reports/audit/alias_exceptions.json').write_text(json.dumps(exceptions,ensure_ascii=False,indent=2))
