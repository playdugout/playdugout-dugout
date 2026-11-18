# Descarga datos de Wikidata (solo lectura) para los futbolistas de top.csv
import csv, json, subprocess, sys, time, os
D = sys.argv[1]; N = int(sys.argv[2])
def q(sparql):
    for attempt in range(4):
        r = subprocess.run(['curl','-sS','-m','120','-G','https://query.wikidata.org/sparql','-H','Accept: application/sparql-results+json',
                            '-H','User-Agent: DugoutDataImport/0.2 (https://playdugout.netlify.app)','--data-urlencode','query='+sparql],capture_output=True,text=True)
        try: return json.loads(r.stdout)['results']['bindings']
        except Exception: time.sleep(5*(attempt+1))
    raise SystemExit('query failed: '+r.stdout[:300]+r.stderr[:300])
rows = list(csv.DictReader(open(os.path.join(D,'top.csv'))))[:N]
pop = {r['p'].rsplit('/',1)[1]: int(r['s']) for r in rows}
cur = set()
if os.path.exists(os.path.join(D,'current_u.csv')):
    for l in open(os.path.join(D,'current_u.csv')):
        if l.strip() and l.startswith('http'):
            qq, v = l.strip().split(','); qq = qq.rsplit('/',1)[1]; pop.setdefault(qq, int(v)); cur.add(qq)
qids = list(pop)
players, stints = {}, []
B = 120
for i in range(0, len(qids), B):
    vals = ' '.join('wd:'+x for x in qids[i:i+B])
    a = q(f'''SELECT ?p ?es ?en ?sport ?cit ?birth WHERE {{ VALUES ?p {{ {vals} }}
      OPTIONAL{{?p rdfs:label ?es FILTER(lang(?es)="es")}} OPTIONAL{{?p rdfs:label ?en FILTER(lang(?en)="en")}}
      OPTIONAL{{?p wdt:P1532 ?sport}} OPTIONAL{{?p wdt:P27 ?cit}} OPTIONAL{{?p wdt:P569 ?birth}} OPTIONAL{{?p wdt:P413 ?pos}} }}''')
    for b in a:
        k = b['p']['value'].rsplit('/',1)[1]; P = players.setdefault(k, {'id':k,'pop':pop[k],'current':k in cur,'sport':[],'cit':[],'pos':[]})
        for f in ('es','en','birth'):
            if f in b: P[f] = b[f]['value']
        for f in ('sport','cit','pos'):
            if f in b:
                v = b[f]['value'].rsplit('/',1)[1]
                if v not in P[f]: P[f].append(v)
    s = q(f'''SELECT ?p ?st ?team ?start ?end ?loan WHERE {{ VALUES ?p {{ {vals} }}
      ?p p:P54 ?st . ?st ps:P54 ?team . OPTIONAL{{?st pq:P580 ?start}} OPTIONAL{{?st pq:P582 ?end}}
      OPTIONAL{{?st pq:P1642 ?loan}} OPTIONAL{{?st pq:P1350 ?apps}} OPTIONAL{{?st pq:P1351 ?goals}} }}''')
    for b in s:
        stints.append({'p':b['p']['value'].rsplit('/',1)[1],'st':b['st']['value'].rsplit('/',1)[1],'team':b['team']['value'].rsplit('/',1)[1],
                       'start':b.get('start',{}).get('value'),'end':b.get('end',{}).get('value'),'loan':b.get('loan',{}).get('value'),'apps':b.get('apps',{}).get('value'),'goals':b.get('goals',{}).get('value')})
    print(i+B, len(stints), flush=True); time.sleep(1)
teams = sorted({s['team'] for s in stints})
tinfo = {}
for i in range(0, len(teams), 200):
    vals = ' '.join('wd:'+x for x in teams[i:i+200])
    for b in q(f'''SELECT ?t ?es ?en ?type WHERE {{ VALUES ?t {{ {vals} }}
      OPTIONAL{{?t rdfs:label ?es FILTER(lang(?es)="es")}} OPTIONAL{{?t rdfs:label ?en FILTER(lang(?en)="en")}}
      OPTIONAL{{?t wdt:P31 ?type}} }}'''):
        k = b['t']['value'].rsplit('/',1)[1]; T = tinfo.setdefault(k, {'types':[]})
        for f in ('es','en'):
            if f in b: T[f] = b[f]['value']
        if 'type' in b:
            v = b['type']['value'].rsplit('/',1)[1]
            if v not in T['types']: T['types'].append(v)
    time.sleep(1)
countries = sorted({c for P in players.values() for c in P['sport']+P['cit']})
cinfo = {}
for i in range(0, len(countries), 200):
    vals = ' '.join('wd:'+x for x in countries[i:i+200])
    for b in q(f'''SELECT ?c ?es ?fifa ?iso2 WHERE {{ VALUES ?c {{ {vals} }}
      OPTIONAL{{?c rdfs:label ?es FILTER(lang(?es)="es")}} OPTIONAL{{?c rdfs:label ?en FILTER(lang(?en)="en")}} OPTIONAL{{?c wdt:P3441 ?fifa}} OPTIONAL{{?c wdt:P297 ?iso2}} OPTIONAL{{?c wdt:P298 ?iso3}} }}'''):
        k = b['c']['value'].rsplit('/',1)[1]; C = cinfo.setdefault(k, {})
        for f in ('es','en','fifa','iso2','iso3'):
            if f in b and f not in C: C[f] = b[f]['value']
    time.sleep(1)
json.dump({'players':players,'stints':stints,'teams':tinfo,'countries':cinfo}, open(os.path.join(D,'raw.json'),'w'), ensure_ascii=False)
print('done', len(players), len(stints), len(tinfo), len(cinfo))
