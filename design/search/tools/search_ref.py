"""Reference implementation of the Lift search spec (§ Search, AC 83-). Python, for the test table only.
The Swift implementation must produce the same order for every row of tests.csv."""
import csv, json, os, re, unicodedata
HERE=os.path.dirname(os.path.abspath(__file__)); OUT=os.path.dirname(HERE)
ROOT=os.path.dirname(os.path.dirname(OUT))
LIB=os.path.join(ROOT,'Packages/LiftKit/Sources/LiftCore/Resources/exercise-library.json')
INV=os.path.join(ROOT,'design/animations/inventory.csv')

def load_rules():
    R={'typo':{},'token':{},'phrase':{},'pair':{},'generic':set(),'keep':set()}
    for r in csv.DictReader(open(os.path.join(OUT,'expansions.csv'))):
        k=r['kind']
        if k=='generic': R['generic'].add(r['from'])
        elif k=='nostem': R['keep'].add(r['from'])
        else: R[k][r['from']]=r['to']
    return R
R=load_rules()

def fold(s):
    s=unicodedata.normalize('NFKD',s.lower()); s=''.join(c for c in s if not unicodedata.combining(c))
    s=s.replace('°',' degree ').replace('&',' and ').replace("'",'').replace('’','')
    s=re.sub(r'(\d)/(\d)',r'\1⁄\2',s)               # keep fractions like 3/4, 90/90 as one token
    s=re.sub(r'[^a-z0-9⁄]+',' ',s)
    s=re.sub(r'(\d)(degree|deg)\b',r'\1 \2',s)
    return s.split()

def stem(t):
    if t in R['keep'] or len(t)<=3 or t.isdigit(): return t
    if t.endswith('ies'): return t[:-3]+'y'
    if t.endswith('es') and re.search(r'(sh|ch|x|ss)es$',t): return t[:-2]
    if t.endswith('s') and not t.endswith('ss') and not t.endswith('us'): return t[:-1]
    return t

def cs(c):
    """Compact form: words joined with nothing, then a final 's' dropped whatever the word length
    (not after 'ss'), so 'Pull-Ups', 'pullups' and 'Pull Ups' all compact to 'pullup'. Spec §10.3 step 5."""
    return c[:-1] if c.endswith('s') and not c.endswith('ss') and len(c)>=4 else c   # 'abs' stays 'abs'

def tokens(s, phrases=True):
    """phrases=False keeps phrase abbreviations (OHP, RDL...) unexpanded: used to decide match-reason meta."""
    out=[]
    for t in fold(s):
        t=R['typo'].get(t,t)
        t=R['token'].get(t,t)
        if phrases: t=R['phrase'].get(t,t)
        out+=t.split()
    out=[stem(t) for t in out]
    # two-token rewrites: "one arm" -> "single arm", "pull down" -> "pulldown"...
    j=' '.join(out)
    for a,b in R['pair'].items(): j=re.sub(r'\b%s\b'%a,b,j)
    return j.split()

_M={'chest':'upper_chest mid_chest lower_chest','pec':'upper_chest mid_chest lower_chest','upper chest':'upper_chest',
 'shoulder':'front_delts side_delts rear_delts','delt':'front_delts side_delts rear_delts','front delt':'front_delts','side delt':'side_delts','rear delt':'rear_delts',
 'back':'lats traps rhomboids lower_back','lat':'lats','trap':'traps','rhomboid':'rhomboids','lower back':'lower_back',
 'arm':'biceps triceps forearms','biceps':'biceps','triceps':'triceps','forearm':'forearms',
 'leg':'quads hamstrings glutes adductors abductors calves','quad':'quads','hamstring':'hamstrings','ham':'hamstrings','glute':'glutes','butt':'glutes',
 'adductor':'adductors','abductor':'abductors','calf':'calves','calve':'calves','core':'abs obliques','abs':'abs','ab':'abs','oblique':'obliques','neck':'neck'}
MUSCLE={k:set(v.split()) for k,v in _M.items() if ' ' not in k}

def dl(a,b):
    d=[[0]*(len(b)+1) for _ in range(len(a)+1)]
    for i in range(len(a)+1): d[i][0]=i
    for j in range(len(b)+1): d[0][j]=j
    for i in range(1,len(a)+1):
        for j in range(1,len(b)+1):
            c=0 if a[i-1]==b[j-1] else 1
            d[i][j]=min(d[i-1][j]+1,d[i][j-1]+1,d[i-1][j-1]+c)
            if i>1 and j>1 and a[i-1]==b[j-2] and a[i-2]==b[j-1]: d[i][j]=min(d[i][j],d[i-2][j-2]+1)
    return d[-1][-1]

def fuzzy_tok(q,k,last):
    if len(q)<4: return None
    if len(q)<5: last=False                      # short tokens: whole-word fuzzy only
    lim=1 if len(q)<8 else 2
    if q[0]!=k[0] and not (len(q)>1 and len(k)>1 and q[0]==k[1] and q[1]==k[0]): return None
    cands=[k]+([k[:n] for n in (len(q),len(q)+1) if 0<n<len(k)] if last else [])
    best=min(dl(q,c) for c in cands)
    return best if best<=lim else None

class Key:
    def __init__(self,text,kind):
        self.text=text; self.kind=kind
        self.t=tokens(text); self.p=' '.join(self.t); self.c=cs(''.join(self.t))
        self.raw=tokens(text,phrases=False); self.rawc=cs(''.join(self.raw))

def tier(qt,key,attrs,generic):
    qp=' '.join(qt); qc=cs(''.join(qt))
    if not qt: return None
    if key.p==qp or key.c==qc or sorted(key.t)==sorted(qt): return 1
    # CDO addendum (deadlift): starts-with and word-start share one tier, so Romanian and Sumo
    # (popularity) beat "Deadlift with Bands/Chains"; starting with the query only breaks ties after rank.
    if key.p.startswith(qp) or key.c.startswith(qc): return 2.9 if not (generic or len(qt)>1) else 3
    # every query token prefixes a distinct key word (any order); attribute words help multi-word queries
    def wp(qtoks, ktoks):
        used=set()
        for q in qtoks:
            hit=next((i for i,k in enumerate(ktoks) if i not in used and k.startswith(q)),None)
            if hit is None: return False
            used.add(hit)
        return True
    for i in range(len(key.t)):
        if ''.join(key.t[i:]).startswith(qc): return 3
    if wp(qt,key.t): return 3
    if len(qt)>1 and any(any(k.startswith(q) for k in key.t) for q in qt) and wp(qt,key.t+attrs): return 3
    if all(any(q in k for k in key.t) for q in qt): return 4   # substring inside a word, never across words
    return None

def fuzzy(qt,key):
    tot=0; used=set()
    for n,q in enumerate(qt):
        best=None
        for i,k in enumerate(key.t):
            if i in used: continue
            d=0 if (k.startswith(q) if n==len(qt)-1 else k==q) else fuzzy_tok(q,k,n==len(qt)-1)
            if d is not None and (best is None or d<best[0]): best=(d,i)
        if best is None: return None
        used.add(best[1]); tot+=best[0]
    return tot if tot>0 else None

class Index:
    def __init__(self):
        lib=json.load(open(LIB))['exercises']
        al={r['exercise_id']:r['aliases'].split('|') for r in csv.DictReader(open(os.path.join(OUT,'aliases.csv')))}
        pop={r['exercise_id']:(int(r['popularity']),int(r['rank']) if r['rank'] else 10**6) for r in csv.DictReader(open(os.path.join(OUT,'popularity.csv')))}
        # v3 fields; the Common list wins a duplicate pair (triceps-pushdown stays, tricep-pushdowns hides)
        dup={e['id']:e['duplicateOf'] for e in lib if e.get('duplicateOf')}
        self.dup=dup; self.E=[]; self.vocab={}
        for e in lib:
            eq=e['equipment'].replace('_',' ')
            self.E.append(dict(id=e['id'],name=e['name'],pop=pop[e['id']],
                keys=[Key(e['name'],'name')]+[Key(a,'alias') for a in al.get(e['id'],[])],
                primary=set(e['primaryMuscles']),
                attrs=tokens(eq)+tokens(e.get('position') or '')))
        for x in self.E:
            if x['id'] in self.dup: continue
            for w in {w for k in x['keys'] for w in k.t}: self.vocab[w]=self.vocab.get(w,0)+1
    def correct(self,qt):
        """Typo correction (§10.2 tier 6): each word of 4+ letters that matches no indexed word is replaced
        by the closest indexed word (Damerau ≤1 for 4-7 letters, ≤2 for 8+, same first letter or swapped
        first pair; the last word may match the start of a word). Ties: more exercises use the word, then A-Z."""
        out=[]; changed=False
        for n,q in enumerate(qt):
            last=n==len(qt)-1
            if any((v.startswith(q) if last else v==q) for v in self.vocab): out.append(q); continue
            c=[(d,-self.vocab[v],v) for v in self.vocab for d in [fuzzy_tok(q,v,last)] if d is not None]
            if c: out.append(min(c)[2]); changed=True
            else: out.append(q)
        return out if changed else None

    def search(self,query,history=()):
        """history: exercise ids, most recent first (stands in for logged-workout counts)."""
        qt=tokens(query); qraw=tokens(query,phrases=False)
        if not qt: return []
        use={i:len(history)-n for n,i in enumerate(history)}
        res=self.rank(qt,qraw,use)
        if len(res)<3:
            fixed=self.correct(qt)
            if fixed:
                seen={r[0] for r in res}
                more=[(i,n,m,6) for i,n,m,t in self.rank(fixed,fixed,use) if i not in seen]
                res+=more[:8]
        return res

    def rank(self,qt,qraw,use):
        generic=len(qt)==1 and qt[0] in R['generic']
        res=[]
        for e in self.E:
            if e['id'] in self.dup and e['id'] not in use: continue
            best=None
            for n,k in enumerate(e['keys']):
                t=tier(qt,k,e['attrs'],generic)
                if not t: continue
                # same tier: the name first, then an alias that echoes what was typed (OHP, RDL), then file order
                pref=(0 if k.kind=='name' else 1 if all(any(w.startswith(q) for w in k.raw) for q in qraw) else 2, n)
                if best is None or (t,pref)<(best[0],best[2]): best=(t,k,pref)
            if best: res.append([3 if best[0]==2.9 else best[0],0 if best[0]==2.9 else 1,e,best[1]])
        # tier 5: a muscle or body-part word ("abs", "chest", "hamstrings") lists exercises that train it
        if len(qt)==1 and qt[0] in MUSCLE:
            seen={r[2]['id'] for r in res}
            for e in self.E:
                if e['id'] in seen or (e['id'] in self.dup and e['id'] not in use): continue
                if MUSCLE[qt[0]] & e['primary']: res.append([5,0,e,e['keys'][0]])
        # your lifts float up: a logged exercise matching at tiers 2-4 sits right after exact matches
        for x in res:
            if x[2]['id'] in use and 3<=x[0]<=4: x[0]=1.5
        res.sort(key=lambda r:(r[0],-use.get(r[2]['id'],0),-r[2]['pop'][0],r[2]['pop'][1],r[1],len(r[2]['name']),r[2]['name']))
        out=[]
        for t,_,e,k in res:
            # match-reason meta: only when the name itself does not show why the row is here
            meta=''
            nk=e['keys'][0]; rc=cs(''.join(qraw))
            def hits(key): return rc in key.rawc or all(any(w.startswith(q) for w in key.raw) for q in qraw)
            if not hits(nk):
                echo=[a for a in e['keys'][1:] if hits(a)]
                typed=''.join(qraw)
                # Nit 1: when no alias equals or starts with the query, the shortest matching alias ("Incline DB Bench")
                sw=lambda a:a.rawc==rc or a.rawc.startswith(rc)
                echo.sort(key=lambda a:(a.rawc!=rc, ''.join(a.raw)!=typed, not a.rawc.startswith(rc), 0 if sw(a) else len(a.text)))   # stable: aliases.csv order breaks ties
                meta=echo[0].text if echo else (k.text if k.kind=='alias' else '')
            out.append((e['id'],e['name'],meta,t))
        return out

if __name__=='__main__':
    import sys
    ix=Index()
    for q in sys.argv[1:]:
        print(q,'->',[(n+(' ['+m+']' if m else ''),t) for i,n,m,t in ix.search(q)[:6]])
