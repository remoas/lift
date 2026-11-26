"""Builds aliases.csv, popularity.csv and expansions.csv for Lift search. Run from anywhere."""
import csv, json, os, sys, re
HERE=os.path.dirname(os.path.abspath(__file__)); OUT=os.path.dirname(HERE)
sys.path.insert(0,HERE)
from alias_data import ADD, REMOVE
from popularity_data import RANK
ROOT=os.path.dirname(os.path.dirname(OUT))
LIB=os.path.join(ROOT,'Packages/LiftKit/Sources/LiftCore/Resources/exercise-library.json')
INV=os.path.join(ROOT,'design/animations/inventory.csv')
D=json.load(open(LIB)); L=D['exercises']; byid={e['id']:e for e in L}
inv={r['id']:r for r in csv.DictReader(open(INV))}
for i in list(ADD)+list(REMOVE)+RANK: assert i in byid, i
assert len(RANK)==len(set(RANK)), [x for x in RANK if RANK.count(x)>1]
def key(s): return re.sub(r'[^a-z0-9]','',s.lower())
names={key(e['name']):e['id'] for e in L}
dup={(r['id'],r['duplicate_of']) for r in inv.values() if r['duplicate_of']}
dropped=[]
UP={'db','bb','kb','ohp','rdl','sldl','bss','rfess','cgbp','ghr','ghd','hspu','tgu','hlr','btn','ctb','c2b','t2b','ttb','dl','bp','ez','sl','cg','v','p','l','y','c&j'}
def nice(a):
    # display casing for match-reason meta: abbreviations upper case, lower-case library aliases title case
    def w(t):
        if t!=t.lower(): return t                     # keep authored casing (RDL, EZ, T-Bar)
        return t.upper() if t in UP else (t if t in ('to','on','with','of','the','and','a','in','from') else t[:1].upper()+t[1:])
    return ' '.join('-'.join(w(p) for p in t.split('-')) for t in a.split(' '))
rows=[]
for e in L:
    rm={key(x) for x in REMOVE.get(e['id'],[])}
    al=[a for a in e['aliases'] if key(a) not in rm]
    al+= [a for a in ADD.get(e['id'],'').split('|') if a]
    seen=set(); out=[]
    for a in al:
        k=key(a)
        o=names.get(k)
        if o and o!=e['id'] and (e['id'],o) not in dup and (o,e['id']) not in dup:
            dropped.append((e['id'],a,o)); continue   # never alias another exercise's own name
        if k and k!=key(e['name']) and k not in seen: seen.add(k); out.append(a.strip())
    if out: rows.append((e['id'],e['name'],[nice(a) for a in out]))
with open(os.path.join(OUT,'aliases.csv'),'w',newline='') as f:
    w=csv.writer(f); w.writerow(['exercise_id','canonical_name','aliases'])
    for i,n,a in rows: w.writerow([i,n,'|'.join(a)])
# popularity
ODD=re.compile(r'\b(with bands|with chains|reverse band|from blocks|plate movers|speed|anti-gravity|pin|board|frankenstein|jefferson|cocoons|car |conans|rickshaw|kneeling squat)\b',re.I)
pop={}
for e in L:
    t=inv[e['id']]['tier']; p={'A':3,'B':2,'C':2}[t]
    if inv[e['id']]['family'] in ('mobility','plyometric'): p=1 if t=='C' else p
    if ODD.search(e['name']): p=1
    if inv[e['id']]['duplicate_of']: p=min(p,2)
    pop[e['id']]=[p,'']
for r,i in enumerate(RANK,1): pop[i]=[5 if r<=30 else 4, r]
with open(os.path.join(OUT,'popularity.csv'),'w',newline='') as f:
    w=csv.writer(f); w.writerow(['exercise_id','name','popularity','rank'])
    for e in sorted(L,key=lambda e:(-pop[e['id']][0], pop[e['id']][1] or 9999, e['name'])):
        w.writerow([e['id'],e['name'],*pop[e['id']]])
# lint: an alias may not equal another exercise's name unless both are known duplicates
issues=[]
for i,n,a in rows:
    for x in a:
        o=names.get(key(x))
        if o and o!=i and (i,o) not in dup and (o,i) not in dup: issues.append((i,x,o))
print('alias rows',len(rows),'aliases',sum(len(a) for _,_,a in rows))
print('dropped (alias = another exercise name):',dropped)
print('lint: alias equals another exercise name:'); [print('  ',t) for t in issues]
