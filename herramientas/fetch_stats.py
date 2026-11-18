# Añade partidos (P1350) y goles (P1351) a cada etapa de raw.json
import json, subprocess, sys, time
R = sys.argv[1]
d = json.load(open(R)); qids = list(d['players'])
def q(sparql):
    for a in range(4):
        r = subprocess.run(['curl','-sS','-m','120','-G','https://query.wikidata.org/sparql','-H','Accept: application/sparql-results+json',
            '-H','User-Agent: DugoutDataImport/0.2 (https://playdugout.netlify.app)','--data-urlencode','query='+sparql],capture_output=True,text=True)
        try: return json.loads(r.stdout)['results']['bindings']
        except Exception: time.sleep(5*(a+1))
    raise SystemExit('fallo: '+r.stdout[:200])
stats = {}
for i in range(0, len(qids), 150):
    vals = ' '.join('wd:'+x for x in qids[i:i+150])
    for b in q(f'SELECT ?st ?apps ?goals WHERE {{ VALUES ?p {{ {vals} }} ?p p:P54 ?st . ?st pq:P1350 ?apps . OPTIONAL{{?st pq:P1351 ?goals}} }}'):
        stats[b['st']['value'].rsplit('/',1)[1]] = (b['apps']['value'], b.get('goals',{}).get('value'))
    time.sleep(1)
n = 0
for s in d['stints']:
    if s['st'] in stats: s['apps'], s['goals'] = stats[s['st']]; n += 1
json.dump(d, open(R,'w'), ensure_ascii=False)
print('etapas con estadísticas', n, 'de', len(d['stints']))
