#!/usr/bin/env python3
import csv,json,re,unicodedata,collections
from pathlib import Path
root=Path(__file__).resolve().parents[2]
def read(p):return list(csv.DictReader(open(root/p,encoding='utf-8-sig',newline='')))
def tokens(s):return re.findall(r'[a-z]+',unicodedata.normalize('NFKD',re.sub(r'\s+\d{4}$','',s)).lower())
def key(s):return ''.join(tokens(s))
def ends(s):
 t=tokens(s);return (t[0],t[-1]) if t else ('','')
schools={'Carnegie Mellon University':'Carnegie Mellon University','University of Illinois Urbana-Champaign':'Univ. of Illinois at Urbana-Champaign','Massachusetts Institute of Technology':'Massachusetts Institute of Technology','Stanford University':'Stanford University','University of California Berkeley':'Univ. of California - Berkeley','University of California San Diego':'Univ. of California - San Diego','University of Washington':'University of Washington','University of Michigan':'University of Michigan','Cornell University':'Cornell University','Georgia Institute of Technology':'Georgia Institute of Technology'}
refs=read('tmp/audit/csrankings.csv');people=read('db/data/manual/faculty_raw.csv');accepted={r['name']:r for r in read('db/data/manual/accepted_author_matches.csv')}
name_overrides={'Christoforos Kozyrakis':'Christos Kozyrakis','Steve Mussmann':'Stephen Mussmann','Ryan Huang':'Peng Huang','Qi (Rose) Yu':'Rose Yu','Alex Rives':'Alexander Rives','Ken Koedinger':'Kenneth Koedinger','Jim Rehg':'James Rehg','Jim McCann':'James McCann','YuFeng (Kevin) Chen':'Yufeng Chen','Qi Tang':'Qi Tang'}
hints=[]
for p in people:
 name=name_overrides.get(p['name'],p['name']);candidates=[r for r in refs if r['affiliation']==schools[p['university']] and (key(r['name'])==key(name) or ends(r['name'])==ends(name))]
 urls=set(r['homepage'].rstrip('/') for r in candidates)
 if not candidates or len(urls)!=1:continue
 valid=[r for r in candidates if r.get('orcid') and r['orcid']!='0000-0000-0000-0000'];r=valid[0] if valid else candidates[0]
 row={'name':p['name'],'university':p['university'],'reference_name':r['name'],'homepage':r['homepage'],'reference_orcid':r.get('orcid') if r.get('orcid')!='0000-0000-0000-0000' else '', 'reference_source':'https://github.com/emeryberger/CSrankings/blob/gh-pages/csrankings.csv'}
 match=accepted.get(p['name']);row['current_id']=match['openalex_id'] if match else ''
 row['current_orcid']=json.loads((root/f'tmp/author_metadata/{match["openalex_id"]}.json').read_text())['author'].get('orcid') if match else ''
 row['orcid_conflict']=bool(row['reference_orcid'] and row['current_orcid'] and row['current_orcid'].split('/')[-1]!=row['reference_orcid'])
 hints.append(row)
with open(root/'reports/audit/reference_hints.csv','w',newline='') as f:
 w=csv.DictWriter(f,fieldnames=list(hints[0]));w.writeheader();w.writerows(hints)
print('Matched hints:',len(hints),'ORCID discrepancies:',sum(r['orcid_conflict'] for r in hints))
for r in hints:
 if r['orcid_conflict'] or r['name'] in ['Steve Mussmann','Ryan Huang','Yiying Zhang','Gang Wang','Wei Hu','Bo Li']:print(r['name'],r['current_id'],r['current_orcid'],r['reference_orcid'],r['homepage'])
