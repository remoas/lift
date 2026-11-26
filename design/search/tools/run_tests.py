"""Runs tests.csv against the reference implementation. Exit 1 on any failure."""
import csv,sys,os
HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
import search_ref as s
ix=s.Index(); fails=0; n=0
for r in csv.DictReader(open(os.path.join(os.path.dirname(HERE),'tests.csv'))):
    n+=1; h=[x for x in r['history'].split('|') if x]
    res=ix.search(r['query'],h); ids=[x[0] for x in res]; why=[]
    if r['expect_top1'] and (not ids or ids[0]!=r['expect_top1']): why.append('top1')
    why+=['top3 '+x for x in r['expect_in_top3'].split('|') if x and x not in ids[:3]]
    why+=['not-top5 '+x for x in r['expect_not_in_top5'].split('|') if x and x in ids[:5]]
    if (res[0][2] if res else '')!=r['expect_meta_top1'] and r['expect_top1']: why.append('meta=%r'%(res[0][2] if res else ''))
    if not r['expect_top1'] and ids: why.append('expected no results')
    if why: fails+=1; print('FAIL',repr(r['query']),r['history'],why,[(a,c) for a,b,c,d in res[:5]])
print(n,'rows,',fails,'failed'); sys.exit(1 if fails else 0)
