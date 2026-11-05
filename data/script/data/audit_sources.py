#!/usr/bin/env python3
"""Independently corroborate sampled paper titles/DOIs on faculty-linked pages.
A missing match is inconclusive, never an automatic rejection.
"""
import json,csv,re,hashlib,time,threading,urllib.request,urllib.parse,urllib.error,unicodedata,concurrent.futures,html,sys
from pathlib import Path
from html.parser import HTMLParser
root=Path(__file__).resolve().parents[2];out=root/'tmp/audit/sources';out.mkdir(parents=True,exist_ok=True)
lock=threading.Lock();hosts={};url_locks={}
def norm(s):return re.sub(r'[^a-z0-9]','',unicodedata.normalize('NFKD',html.unescape(s or '')).lower())
class Page(HTMLParser):
 def __init__(self):super().__init__();self.parts=[];self.links=[];self.a=None;self.hide=0
 def handle_starttag(self,t,a):
  d=dict(a)
  if t in ('script','style'):self.hide+=1
  if t=='a':self.a=[d.get('href',''),'']
 def handle_endtag(self,t):
  if t in ('script','style'):self.hide=max(0,self.hide-1)
  if t=='a' and self.a:self.links.append(self.a);self.a=None
 def handle_data(self,s):
  if not self.hide:self.parts.append(s)
  if self.a:self.a[1]+=' '+s
 def text(self):return ' '.join(self.parts)
def fetch(url):
 fp=hashlib.sha256(url.encode()).hexdigest();path=out/(fp+'.json')
 with lock:ul=url_locks.setdefault(url,threading.Lock())
 with ul:
  if path.exists():return json.loads(path.read_text())
  host=urllib.parse.urlparse(url).netloc
  with lock:
   now=time.monotonic();wait=max(0,hosts.get(host,0)-now);hosts[host]=now+wait+.45
  if wait:time.sleep(wait)
  result={'url':url,'retrieved_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
  try:
   req=urllib.request.Request(url,headers={'User-Agent':'NicheRank-course-data-audit/1.0','Accept':'text/html,application/xhtml+xml'})
   with urllib.request.urlopen(req,timeout=14) as r:
    body=r.read(2500000);typ=r.headers.get('Content-Type','');result.update(status=r.status,final_url=r.url)
    if 'pdf' in typ:result.update(text='',links=[],note='PDF not automatically extracted')
    else:
     content=body.decode(r.headers.get_content_charset() or 'utf-8',errors='replace');p=Page();p.feed(content)
     result.update(text=p.text(),raw=content,links=p.links,sha256=hashlib.sha256(body).hexdigest())
  except Exception as e:result.update(status=0,error=type(e).__name__,text='',raw='',links=[])
  tmp=path.with_suffix('.tmp');tmp.write_text(json.dumps(result,ensure_ascii=False));tmp.replace(path)
  return result
special={'Tom Costello':'https://thcostello.com/','Christoforos Kozyrakis':'https://christos.kozyrakis.org/','Yiying Zhang':'https://cseweb.ucsd.edu/~yiying/','Michael Kim':'https://www.cs.cornell.edu/~mpkim/pubs.html','Qi Tang':'https://tangqi.github.io/','Bo Li':'https://aisecure.github.io/PUBLICATIONS/index.html','Gang Wang':'https://gangw.cs.illinois.edu/','Hao Peng':'https://haopeng-nlp.github.io/','Wei Hu':'https://weihu.me/','Ryan Huang':'https://web.eecs.umich.edu/~ryanph/','Merrick Furst':'https://www.cc.gatech.edu/people/merrick-furst','Will Perkins':'https://willperkins.org/','Steve Mussmann':'https://steve.mussmann.us/'}
items=json.loads((root/'tmp/audit/author_samples.json').read_text())
hint_mode='--hints' in sys.argv
hints={r['name']:r['homepage'] for r in csv.DictReader(open(root/'reports/audit/reference_hints.csv'))}
if hint_mode:items=[x for x in items if x['professor']['name'] in hints]
def audit(item):
 p=item['professor'];id=p['openalex_id'];result_path=root/f'tmp/audit/{"source_results_hints" if hint_mode else "source_results"}/{id}.json';result_path.parent.mkdir(parents=True,exist_ok=True)
 if result_path.exists() and '--reevaluate' not in sys.argv:return json.loads(result_path.read_text())
 url=special.get(p['name'],hints.get(p['name'],p['evidence_url'].split(';')[0].strip()) if hint_mode else p['evidence_url'].split(';')[0].strip())
 if hint_mode and url.startswith('http://'):url='https://'+url[7:]
 pages=[fetch(url)]
 def matches():
  found=[]
  for w in item['samples']:
   for page in pages:
    title=norm(w.get('title'));doi=(w.get('doi') or '').replace('https://doi.org/','').lower()
    title_ok=len(title)>=25 and len((w.get('title') or '').split())>=4 and title in norm(page.get('text','')+' '+page.get('raw',''))
    doi_ok=bool(doi and doi in urllib.parse.unquote(page.get('raw','')).lower())
    if title_ok or doi_ok:found.append({'work_id':w['id'],'source_url':page.get('final_url',page['url']),'evidence':'doi' if doi_ok else 'exact_normalized_title','title':w.get('title')});break
  return found
 hits=matches()
 if len(hits)<min(2,len(item['samples'])):
  candidates=[]
  for href,label in pages[0].get('links',[]):
   target=urllib.parse.urljoin(pages[0].get('final_url',url),href);parsed=urllib.parse.urlparse(target)
   if parsed.scheme not in ('http','https') or re.search(r'\.(pdf|jpg|png|zip|bib)$',parsed.path,re.I):continue
   if any(h in parsed.netloc.lower() for h in ('google.com','twitter.com','facebook.com','linkedin.com','youtube.com','scholar.google','orcid.org','github.com')):continue
   score=0
   if re.search(r'\b(publications?|papers|personal (web|home)|home ?page|faculty website|research website)\b',label,re.I):score+=4
   if re.search(r'(pubs|publications|papers)([./_-]|$)',parsed.path,re.I):score+=3
   if 'research' in label.lower() and parsed.netloc==urllib.parse.urlparse(url).netloc:score+=1
   if target.rstrip('/')==url.rstrip('/') or '#' in target and target.split('#')[0].rstrip('/')==url.rstrip('/'):continue
   if score>=3:candidates.append((score,target.split('#')[0]))
  seen={url,pages[0].get('final_url')}
  for _,target in sorted(candidates,reverse=True):
   if target in seen:continue
   seen.add(target);pages.append(fetch(target));hits=matches()
   if len(hits)>=min(2,len(item['samples'])) or len(pages)>=3:break
 result={'professor_openalex_id':id,'name':p['name'],'university':p['university'],'sample_count':len(item['samples']),'corroborated_samples':hits,'sources':[x.get('final_url',x['url']) for x in pages],'http_statuses':[x['status'] for x in pages],'status':'independent_sample_corroborated' if hits else 'no_sample_on_checked_pages' if item['samples'] else 'zero_papers_requires_review'}
 result_path.write_text(json.dumps(result,ensure_ascii=False,indent=2));return result
results=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
 futures=[pool.submit(audit,x) for x in items]
 for f in concurrent.futures.as_completed(futures):
  results.append(f.result())
  if len(results)%25==0:print(f'{len(results)}/{len(items)} profiles checked; {sum(bool(r["corroborated_samples"]) for r in results)} with independent publication evidence',flush=True)
results.sort(key=lambda r:(r['university'],r['name']))
(root/('reports/audit/independent_sample_evidence_hints.json' if hint_mode else 'reports/audit/independent_sample_evidence.json')).write_text(json.dumps(results,ensure_ascii=False,indent=2))
summary={'profiles_checked':len(results),'profiles_with_independently_corroborated_sample':sum(bool(r['corroborated_samples']) for r in results),'sample_papers_corroborated':sum(len(r['corroborated_samples']) for r in results),'inconclusive_or_zero':sum(not r['corroborated_samples'] for r in results)}
(root/('reports/audit/independent_sample_summary_hints.json' if hint_mode else 'reports/audit/independent_sample_summary.json')).write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
