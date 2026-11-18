# Descarga de Wikidata (solo lectura) para una lista de futbolistas.
# Uso: python3 fetch_wd2.py players.json raw.json
#   players.json = {"Q615": {"pop": 228, "current": true}, ...}
# Guarda jugadores (nombre, nacimiento, fallecimiento, fin de carrera, posición, país),
# etapas en clubes (con partidos y goles de liga), clubes y países, en el mismo formato que usa build_players.py.
import json, subprocess, sys, time
SRC, OUT = sys.argv[1], sys.argv[2]
UA = 'DugoutDataImport/0.3 (https://playdugout.netlify.app)'
def q(sparql):
    for a in range(5):
        r = subprocess.run(['curl', '-sS', '-m', '170', '-G', 'https://query.wikidata.org/sparql', '-H', 'Accept: application/sparql-results+json',
                            '-H', 'User-Agent: ' + UA, '--data-urlencode', 'query=' + sparql], capture_output=True, text=True)
        try: return json.loads(r.stdout)['results']['bindings']
        except Exception: time.sleep(8 * (a + 1))
    raise SystemExit('query failed: ' + r.stdout[:300] + r.stderr[:300])
qid = lambda b, k: b[k]['value'].rsplit('/', 1)[1]
src = json.load(open(SRC)); qids = list(src)
players, stints = {}, []
B = 100
for i in range(0, len(qids), B):
    vals = ' '.join('wd:' + x for x in qids[i:i + B])
    for b in q(f'''SELECT ?p ?es ?en ?sport ?cit ?birth ?death ?wend ?pos WHERE {{ VALUES ?p {{ {vals} }}
      OPTIONAL{{?p rdfs:label ?es FILTER(lang(?es)="es")}} OPTIONAL{{?p rdfs:label ?en FILTER(lang(?en)="en")}}
      OPTIONAL{{?p wdt:P1532 ?sport}} OPTIONAL{{?p wdt:P27 ?cit}} OPTIONAL{{?p wdt:P569 ?birth}}
      OPTIONAL{{?p wdt:P570 ?death}} OPTIONAL{{?p wdt:P2032 ?wend}} OPTIONAL{{?p wdt:P413 ?pos}} }}'''):
        k = qid(b, 'p'); s = src[k]
        P = players.setdefault(k, {'id': k, 'pop': s['pop'], 'current': bool(s.get('current')), 'sport': [], 'cit': [], 'pos': []})
        for f in ('es', 'en', 'birth', 'death', 'wend'):
            if f in b and f not in P: P[f] = b[f]['value']
        for f in ('sport', 'cit', 'pos'):
            if f in b:
                v = qid(b, f)
                if v not in P[f]: P[f].append(v)
    for b in q(f'''SELECT ?p ?st ?team ?start ?end ?loan ?apps ?goals WHERE {{ VALUES ?p {{ {vals} }}
      ?p p:P54 ?st . ?st ps:P54 ?team . OPTIONAL{{?st pq:P580 ?start}} OPTIONAL{{?st pq:P582 ?end}}
      OPTIONAL{{?st pq:P1642 ?loan}} OPTIONAL{{?st pq:P1350 ?apps}} OPTIONAL{{?st pq:P1351 ?goals}} }}'''):
        stints.append({'p': qid(b, 'p'), 'st': b['st']['value'].rsplit('/', 1)[1], 'team': qid(b, 'team'),
                       'start': b.get('start', {}).get('value'), 'end': b.get('end', {}).get('value'), 'loan': b.get('loan', {}).get('value'),
                       'apps': b.get('apps', {}).get('value'), 'goals': b.get('goals', {}).get('value')})
    print(min(i + B, len(qids)), 'players', len(stints), 'stints', flush=True); time.sleep(1)
# Una etapa puede salir repetida si tiene varios valores de un calificador: nos quedamos con una
seen = {};
for s in stints: seen.setdefault(s['st'], s)
stints = list(seen.values())
teams = sorted({s['team'] for s in stints}); tinfo = {}
for i in range(0, len(teams), 200):
    vals = ' '.join('wd:' + x for x in teams[i:i + 200])
    for b in q(f'''SELECT ?t ?es ?en ?type ?country WHERE {{ VALUES ?t {{ {vals} }}
      OPTIONAL{{?t rdfs:label ?es FILTER(lang(?es)="es")}} OPTIONAL{{?t rdfs:label ?en FILTER(lang(?en)="en")}}
      OPTIONAL{{?t wdt:P31 ?type}} OPTIONAL{{?t wdt:P17 ?country}} }}'''):
        k = qid(b, 't'); T = tinfo.setdefault(k, {'types': [], 'country': []})
        for f in ('es', 'en'):
            if f in b: T[f] = b[f]['value']
        for f, key in (('type', 'types'), ('country', 'country')):
            if f in b:
                v = qid(b, f)
                if v not in T[key]: T[key].append(v)
    print('teams', min(i + 200, len(teams)), flush=True); time.sleep(1)
countries = sorted({c for P in players.values() for c in P['sport'] + P['cit']}); cinfo = {}
for i in range(0, len(countries), 200):
    vals = ' '.join('wd:' + x for x in countries[i:i + 200])
    for b in q(f'''SELECT ?c ?es ?en ?fifa ?iso2 ?iso3 WHERE {{ VALUES ?c {{ {vals} }}
      OPTIONAL{{?c rdfs:label ?es FILTER(lang(?es)="es")}} OPTIONAL{{?c rdfs:label ?en FILTER(lang(?en)="en")}}
      OPTIONAL{{?c wdt:P3441 ?fifa}} OPTIONAL{{?c wdt:P297 ?iso2}} OPTIONAL{{?c wdt:P298 ?iso3}} }}'''):
        k = qid(b, 'c'); C = cinfo.setdefault(k, {})
        for f in ('es', 'en', 'fifa', 'iso2', 'iso3'):
            if f in b and f not in C: C[f] = b[f]['value']
    time.sleep(1)
pos = sorted({x for P in players.values() for x in P['pos']}); plab = {}
for i in range(0, len(pos), 200):
    vals = ' '.join('wd:' + x for x in pos[i:i + 200])
    for b in q(f'SELECT ?x ?l WHERE {{ VALUES ?x {{ {vals} }} ?x rdfs:label ?l FILTER(lang(?l)="en") }}'):
        plab[qid(b, 'x')] = b['l']['value']
json.dump({'players': players, 'stints': stints, 'teams': tinfo, 'countries': cinfo, 'positions': plab}, open(OUT, 'w'), ensure_ascii=False)
print('done', len(players), 'players', len(stints), 'stints', len(tinfo), 'teams', len(cinfo), 'countries')
