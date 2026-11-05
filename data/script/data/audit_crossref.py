#!/usr/bin/env python3
"""Publisher-deposited corroboration for one DOI sample per inconclusive profile.
Name-only matches are explicitly not classified as verified authorship.
"""
import json,csv,re,unicodedata,urllib.request,urllib.parse,time,threading,concurrent.futures,hashlib,collections
from pathlib import Path
root=Path(__file__).resolve().parents[2];cache=root/'tmp/audit/crossref';cache.mkdir(parents=True,exist_ok=True)
lock=threading.Lock();last=0;doi_locks={}
def norm(s):return re.sub('[^a-z0-9]','',unicodedata.normalize('NFKD',s or '').lower())
def name_ok(a,b):
 x,y=re.findall('[a-z]+',unicodedata.normalize('NFKD',a).lower()),re.findall('[a-z]+',unicodedata.normalize('NFKD',b).lower())
 return bool(x and y and x[-1]==y[-1] and x[0]==y[0])
def get(doi):
 global last
 path=cache/(hashlib.sha256(doi.encode()).hexdigest()+'.json')
 with lock:dl=doi_locks.setdefault(doi,threading.Lock())
 with dl:
  if path.exists():return json.loads(path.read_text())
  with lock:
   delay=max(0,.35-(time.monotonic()-last))
   if delay:time.sleep(delay)
   last=time.monotonic()
  j={'doi':doi,'retrieved_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
  try:
   req=urllib.request.Request('https://api.crossref.org/works/'+urllib.parse.quote(doi,safe=''),headers={'User-Agent':'NicheRank-course-data-audit/1.0','Accept':'application/json'})
   with urllib.request.urlopen(req,timeout=12) as r:
    msg=json.load(r).get('message',{});j.update(status=r.status,message={k:msg[k] for k in ['title','author','DOI','relation','type'] if k in msg})
  except Exception as e:j.update(status=getattr(e,'code',0),error=type(e).__name__)
  path.write_text(json.dumps(j,ensure_ascii=False));return j
screen={r['baseline_openalex_id']:r for r in csv.DictReader(open(root/'reports/audit/author_audit_results.csv'))};items=json.loads((root/'tmp/audit/author_samples.json').read_text())
items=[i for i in items if screen[i['professor']['openalex_id']]['status'] in ['screened_independent_sample_inconclusive','independent_identifier_consistent_sample_not_corroborated']]
alias_school={'Massachusetts Institute of Technology':['massachusettsinstituteoftechnology','mitcambridge'],'University of Illinois Urbana-Champaign':['universityofillinois','illinoisurbanachampaign'],'University of California Berkeley':['universityofcaliforniaberkeley','ucberkeley'],'University of California San Diego':['universityofcaliforniasandiego','ucsandiego'],'Georgia Institute of Technology':['georgiainstituteoftechnology','georgiatech']}
def audit(i):
 p=i['professor'];id=p['openalex_id'];samples=sorted(i['samples'],key=lambda w:w.get('date') or '',reverse=True)
 sample=next((w for w in samples if w.get('doi') and not w['doi'].startswith('https://doi.org/10.48550/')),None)
 result={'professor_openalex_id':id,'name':p['name'],'university':p['university'],'status':'no_crossref_doi_sample'}
 if not sample:return result
 doi=sample['doi'].replace('https://doi.org/','');j=get(doi);msg=j.get('message',{});meta=json.loads((root/f'tmp/author_metadata/{id}.json').read_text())['author'];orcid=(meta.get('orcid') or '').split('/')[-1];matches=[]
 for author in msg.get('author',[]):
  n=author.get('given','')+' '+author.get('family','');ident=(author.get('ORCID') or '').split('/')[-1]
  if not (name_ok(n,p['name']) or name_ok(n,p['source_display_name'])):continue
  affiliation=' '.join(x.get('name','') for x in author.get('affiliation',[]));school=norm(p['university']);aff=norm(affiliation)
  affiliation_ok=any(x in aff for x in alias_school.get(p['university'],[school]))
  evidence='publisher_orcid_and_name' if orcid and ident==orcid else 'publisher_name_and_current_institution' if affiliation_ok else 'publisher_name_only_inconclusive'
  matches.append({'publisher_name':n,'publisher_orcid':ident,'publisher_affiliation':affiliation,'evidence':evidence})
 strong=[m for m in matches if m['evidence']!='publisher_name_only_inconclusive']
 result.update(work_id=sample['id'],doi=doi,title=sample['title'],source_url='https://api.crossref.org/works/'+urllib.parse.quote(doi,safe=''),publisher_matches=matches,http_status=j['status'],status='publisher_corroborated' if strong else 'publisher_evidence_inconclusive')
 return result
rows=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 for f in concurrent.futures.as_completed([pool.submit(audit,i) for i in items]):
  rows.append(f.result())
  if len(rows)%50==0:print(f'{len(rows)}/{len(items)} publisher checks; {sum(r["status"]=="publisher_corroborated" for r in rows)} corroborated',flush=True)
rows.sort(key=lambda r:r['name']);(root/'reports/audit/publisher_sample_evidence.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
summary={'profiles_checked':len(rows),'statuses':dict(collections.Counter(r['status'] for r in rows)),'method':'One newest available non-arXiv DOI sample per profile lacking faculty-page sample evidence; require name plus ORCID or current institution. Name-only matches remain inconclusive.'}
(root/'reports/audit/publisher_sample_summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
