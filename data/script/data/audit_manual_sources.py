#!/usr/bin/env python3
import urllib.request,concurrent.futures,json,hashlib,time
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=root/'tmp/audit/manual_sources';out.mkdir(parents=True,exist_ok=True)
sources={
'Tom Costello':['https://thcostello.com/','https://www.hcii.cmu.edu/people/tom-costello'],
'Christoforos Kozyrakis':['https://christos.kozyrakis.org/','https://mast.stanford.edu/','https://mast.stanford.edu/pubs','https://mast.stanford.edu/publications/'],
'Xiuwei Zhang':['https://xiuweizhang.wordpress.com/','https://xiuweizhang.wordpress.com/publications/'],
'John Wright':['https://people.eecs.berkeley.edu/~jswright/'],
'Lin Ma':['https://web.eecs.umich.edu/~linmacse/'],
'Jason Li':['https://q3r.github.io/'],
'Qi Tang':['https://tangqi.github.io/','https://tangqi.github.io/publications/'],
'Yiying Zhang':['https://cseweb.ucsd.edu/~yiying/','https://cseweb.ucsd.edu/~yiying/publication.html'],
'Bo Li':['https://aisecure.github.io/','https://aisecure.github.io/PUBLICATIONS/index.html'],
'Gang Wang':['https://gangw.cs.illinois.edu/'],
'Ryan Huang':['https://web.eecs.umich.edu/~ryanph/','https://www.cs.jhu.edu/~huang/pubs.html'],
'Wei Hu':['https://weihu.me/'],
'Hao Peng':['https://haopeng-nlp.github.io/','https://haopeng-nlp.github.io/publications/'],
'Michael Kim':['https://www.cs.cornell.edu/~mpkim/pubs.html'],
'Will Perkins':['https://willperkins.org/'],
'Steve Mussmann':['https://steve.mussmann.us/','https://proceedings.mlr.press/v119/koh20a.html'],
'Merrick Furst':['https://www.cc.gatech.edu/people/merrick-furst'],
'Ari Lightman':['https://www.heinz.cmu.edu/faculty-research/profiles/lightman-ari'],
'Dimitrios S Apostolopoulos':['https://www.ri.cmu.edu/ri-faculty/dimitrios-dimi-apostolopoulos/'],
'Adam Paulisick':['https://lti.cmu.edu/people/faculty/paulisick-adam.html'],
'Ana Maria Sande do Vale Pinto da Silva':['https://www.design.cmu.edu/news/ana-maria-pinto-da-silva-begins-role-head-carnegie-mellon-universitys-school-design']}
def get(pair):
 name,url=pair;fp=hashlib.sha256(url.encode()).hexdigest();p=out/(fp+'.json')
 if p.exists():return json.loads(p.read_text())
 j={'name':name,'url':url,'retrieved_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
 try:
  req=urllib.request.Request(url,headers={'User-Agent':'NicheRank-course-data-audit/1.0'})
  with urllib.request.urlopen(req,timeout=20) as r:
   b=r.read(3000000);j.update(status=r.status,final_url=r.url,raw=b.decode('utf-8',errors='replace'),sha256=hashlib.sha256(b).hexdigest())
 except Exception as e:j.update(status=0,error=type(e).__name__,raw='')
 p.write_text(json.dumps(j,ensure_ascii=False));return j
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
 for j in pool.map(get,[(n,u) for n,urls in sources.items() for u in urls]):print(j['name'],j['status'],j['url'],flush=True)
