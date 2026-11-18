# Convierte raw.json (Wikidata) + la base curada del prototipo en js/players.js y supabase/02_cartas.sql
import json, re, sys, unicodedata, collections, os
RAW, PROTO, OUTJS, OUTSQL = sys.argv[1:5]
d = json.load(open(RAW))
P, S, T, C = d['players'], d['stints'], d['teams'], d['countries']
NOW = 2026
MAJOR = {"Q8682":"RMA","Q7156":"FCB","Q8701":"ATM","Q10329":"SEV","Q10333":"VAL","Q12297":"VIL","Q8723":"BET","Q8687":"ATH",
 "Q10315":"RSO","Q5549552":"RSO","Q18656":"MUN","Q50602":"MCI","Q1130849":"LIV","Q9616":"CHE","Q9617":"ARS","Q18741":"TOT",
 "Q1422":"JUV","Q1543":"MIL","Q55602896":"MIL","Q631":"INT","Q2641":"NAP","Q2739":"ROM","Q15789":"BAY","Q41420":"BVB",
 "Q483020":"PSG","Q180305":"MON","Q704":"LYO","Q132885":"MAR","Q131499":"BEN","Q128446":"POR","Q75729":"SPO","Q81888":"AJA",
 "Q11938":"PSV","Q170703":"BOC","Q15799":"RIV","Q16844931":"INM","Q482764":"ALN","Q104761":"LEV","Q19593":"CEL","Q495299":"GAL",
 "Q73965":"HIL","Q32494":"SCH","Q216032":"GEN","Q101859":"WOL","Q285131":"WOL"}
NAT_TYPES = {"Q6979593","Q135408445","Q6979740","Q23901123","Q21945604","Q1203196","Q23901137","Q23904671","Q23759293","Q23904672"}
WOMEN_TYPES = {"Q51481377","Q28140340"}
RESERVE_TYPES = {"Q2412834"}
BAD_LABEL = re.compile(r"(national|olympic|selecci[oó]n|\bU-?\d{2}\b|under-\d+|sub-\d+|\byouth\b|juvenil|castilla|promesas|primavera|reserves?\b|academy|\bjong\b|atl[eè]tic\b(?!o)|mestalla|bilbao athletic|sevilla atl[eé]tico|fabril|next gen|\bII\b|\bIII\b|\"?\bB\"?$|\"B\"|\"C\"|\bC$|amateure|cantera|development squad|women|femenin|f[eé]minine|ladies|frauen|w\.f\.c\.|\bwfc\b)", re.I)
def norm(s): return unicodedata.normalize('NFD', s).encode('ascii','ignore').decode().lower().strip()
LONG = [r'Association Football Club', r'Football Club', r'Fútbol Club', r'Futebol Clube', r'Club de Fútbol', r'Spor Kulübü', r'Sport Club', r'Società Sportiva', r'Associazione Calcio', r'Unione Calcio', r'Calcio \d{4}', r'Clube de Regatas do', r'Club Atlético', r'Real Club Deportivo', r'Club Deportivo', r'Unión Deportiva', r'Sociedad Deportiva', r'Sporting Clube de']
ABBR = {'FC','CF','AFC','SC','SE','CA','CD','UD','RCD','AS','AC','SS','SSC','US','ACF','FK','NK','GNK','HŠK','SK','PFC','RC','OGC','OSC','SL','SV','TSG','FSV','CR','EC','KRC','RSC','SAD','JK','IF','BK','FF','AIK','CFC','FBC','SpVgg','TSV','KV','KAA','RKC','SBV','PSV','AZ','NAC','FBPA','SFC','CSD','SCC','GD','CFR','CS','OFK','PAOK','AEK'} - {'PSV','AZ','NAC','PAOK','AEK','AIK'}
def clean(name):
    s = name
    for pat in LONG: s = re.sub(pat, '', s)
    s = re.sub(r'^1\.\s*', '', s)
    toks = [t for t in re.split(r'\s+', s) if t]
    keep = [t for t in toks if t.replace('.', '') not in ABBR]
    s = ' '.join(keep) if keep else s
    s = re.sub(r'\s{2,}', ' ', s).strip(' -,.&')
    return s if len(s) >= 3 else name.strip()
def short(name, alt=None):
    cands = [clean(x) for x in (name, alt) if x]
    return min(cands, key=len)
def team_ok(t):
    I = T.get(t, {}); types = set(I.get('types', []))
    lab = (I.get('en', '') + ' | ' + I.get('es', ''))
    if t in MAJOR: return True
    if types & NAT_TYPES or types & RESERVE_TYPES or types & WOMEN_TYPES: return False
    if BAD_LABEL.search(lab): return False
    return bool(I.get('en') or I.get('es'))
def team_key(t):
    if t in MAJOR: return MAJOR[t]
    I = T[t]; return short(I.get('en') or I.get('es'))
def season(v, is_end):
    m = re.match(r'(-?\d{4})-(\d{2})-(\d{2})', v or '')
    if not m: return None
    y, mo, da = int(m[1]), int(m[2]), int(m[3])
    if mo == 1 and da == 1: return y            # fecha con precisión de año
    return y if (is_end or mo >= 6) else y - 1
# --- jugadores de Wikidata ---
def _num(v):
    try: return str(float(v))
    except Exception: return None
for _s in S:
    _s['apps'] = _num(_s.get('apps')); _s['goals'] = _num(_s.get('goals'))
S_ALL = collections.defaultdict(list)
for s in S: S_ALL[s['p']].append(s)
POSL = d.get('positions', {})
women = set()
by_p = collections.defaultdict(list)
for s in S:
    I = T.get(s['team'], {})
    if set(I.get('types', [])) & WOMEN_TYPES or re.search(r'women|femenin|f[eé]minine|ladies|frauen|w\.f\.c\.', I.get('en', '') + I.get('es', ''), re.I): women.add(s['p'])
    if team_ok(s['team']): by_p[s['p']].append(s)
def flag(iso2, fifa):
    if fifa == 'ENG': return '🏴\U000E0067\U000E0062\U000E0065\U000E006E\U000E0067\U000E007F'
    if fifa == 'SCO': return '🏴\U000E0067\U000E0062\U000E0073\U000E0063\U000E0074\U000E007F'
    if fifa == 'WAL': return '🏴\U000E0067\U000E0062\U000E0077\U000E006C\U000E0073\U000E007F'
    if iso2 and len(iso2) == 2: return ''.join(chr(0x1F1E6 + ord(c) - 65) for c in iso2.upper())
    return '🏳️'
nats = {}
ISO3_FIFA = {'DEU':'GER','NLD':'NED','CHE':'SUI','PRT':'POR','HRV':'CRO','URY':'URU','DNK':'DEN','BGR':'BUL','GRC':'GRE','CHL':'CHI',
 'CRI':'CRC','DZA':'ALG','SAU':'KSA','ZAF':'RSA','PRY':'PAR','TGO':'TOG','AGO':'ANG','GIN':'GUI','ZMB':'ZAM','ZWE':'ZIM','MYS':'MAS',
 'VNM':'VIE','PHL':'PHI','GTM':'GUA','HND':'HON','TTO':'TRI','HTI':'HAI','KWT':'KUW','ARE':'UAE','LBN':'LIB','GMB':'GAM','MDG':'MAD',
 'BGD':'BAN','NPL':'NEP','SLV':'SLV','IRN':'IRN','IDN':'IDN','LVA':'LVA','OMN':'OMA','BHR':'BHR','NGA':'NGA','CPV':'CPV','SVN':'SVN',
 'MNG':'MGL','KHM':'CAM','SGP':'SIN','LKA':'SRI','TWN':'TPE','CHN':'CHN','MAC':'MAC','SDN':'SDN','LBY':'LBY','TZA':'TAN','PRI':'PUR'}
HOME = {'Q21':('ENG','England'),'Q22':('SCO','Scotland'),'Q25':('WAL','Wales'),'Q26':('NIR','Northern Ireland')}
ENNAME = {'NED':'Netherlands','USA':'United States','KOR':'South Korea','PRK':'North Korea','CZE':'Czech Republic','RUS':'Russia','CIV':"Côte d'Ivoire",'COD':'DR Congo','IRN':'Iran','BIH':'Bosnia and Herzegovina','MKD':'North Macedonia','TUR':'Türkiye','CHN':'China','TPE':'Taiwan','VEN':'Venezuela','BOL':'Bolivia','URS':'Soviet Union','TCH':'Czechoslovakia','YUG':'Yugoslavia','GDR':'East Germany','FRG':'West Germany'}
def nat_of(p):
    for c in p['sport'] + p['cit']:
        if c in HOME:
            code, name = HOME[c]
            if code not in nats: nats[code] = [name, flag(None, code) if code != 'NIR' else '🇬🇧']
            return code
        ci = C.get(c, {})
        iso3 = (ci.get('iso3') or '').upper()
        code = ci.get('fifa') or ISO3_FIFA.get(iso3, iso3)
        if code:
            if code not in nats: nats[code] = [ENNAME.get(code) or ci.get('en') or ci.get('es') or code, flag(ci.get('iso2'), code)]
            return code
    return None
wd = []
for k, p in P.items():
    if k in women: continue
    name = p.get('en') or p.get('es')
    if not name or re.match(r'^Q\d+$', name): continue
    st = []
    by = int(p['birth'][:4]) if p.get('birth', '')[:4].isdigit() else None
    caps = ig = None
    for s in S_ALL.get(k, []):
        lab = T.get(s['team'], {}).get('en', '')
        if re.search(r'national', lab, re.I) and not re.search(r'under|U-?\d|olympic|youth|amateur|women|\bB\b|futsal|beach|regional|autonomous', lab, re.I) and s.get('apps'):
            caps = int(float(s['apps'])); ig = int(float(s['goals'] or 0))
    labs = ' | '.join(POSL.get(x, '').lower() for x in p.get('pos', []))
    pos = ('GK' if re.search(r'goal|gate', labs) else 'FWD' if re.search(r'forward|striker|attacker|winger', labs)
           else 'MID' if re.search(r'midfield|playmaker|wing half|centerhalf', labs) else 'DEF' if re.search(r'back|defender|sweeper|stopper', labs) else None)
    for s in by_p.get(k, []):
        a = season(s['start'], False)
        if a is None or a < 1950: continue
        e0 = season(s['end'], True)
        if by and e0 and e0 <= by + 17: continue      # equipo de cantera
        if by and a < by + 16: a = by + 16
        b = season(s['end'], True)
        st.append([team_key(s['team']), a, b, s.get('apps'), s.get('goals')])
    if not st: continue
    st.sort(key=lambda x: (x[1], x[2] if x[2] else 9999))
    # fin desconocido: hasta el inicio de la siguiente etapa, o hasta hoy si es la última
    for i, x in enumerate(st):
        if x[2] is None:
            nxt = [y[1] for y in st[i+1:] if y[1] > x[1]]
            x[2] = min(nxt) if nxt else NOW
        x[2] = min(max(x[2], x[1] + 1), NOW)
    # unir etapas seguidas en el mismo club
    merged = []
    for x in st:
        if merged and merged[-1][0] == x[0] and x[1] <= merged[-1][2]:
            m = merged[-1]; m[2] = max(m[2], x[2])
            m[3] = None if (m[3] is None or x[3] is None) else str(float(m[3]) + float(x[3]))
            m[4] = None if (m[4] is None and x[4] is None) else str(float(m[4] or 0) + float(x[4] or 0))
        else: merged.append(list(x))
    # estadísticas de liga: solo si TODAS las etapas tienen partidos registrados
    complete = all(x[3] is not None for x in merged)
    la = sum(int(float(x[3])) for x in merged) if complete else None
    lg = sum(int(float(x[4] or 0)) for x in merged) if complete else None
    merged = [x[:3] for x in merged]
    nat = nat_of(p)
    if not nat: continue
    wd.append({'name': name, 'nat': nat, 'pop': p['pop'], 'st': merged, 'alt': {norm(p.get('es', '')), norm(p.get('en', ''))},
               'la': la, 'lg': lg, 'caps': caps, 'ig': ig, 'pos': pos, 'cur': bool(merged) and merged[-1][2] >= NOW, 'by': by})
# --- base curada del prototipo ---
src = open(PROTO, encoding='utf-8').read()
raw = src[src.index('const RAW = `') + 13: src.index('`;', src.index('const RAW = `'))]
cur = []
for l in raw.strip().split('\n'):
    n, nat, c = l.split('|')
    st = []
    for x in c.split(';'):
        k = x.rfind(':'); a, b = x[k+1:].split('-'); st.append([x[:k], int(a), int(b)])
    cur.append({'name': n, 'nat': nat, 'st': st})
majors = lambda st: {x[0] for x in st if x[0] in set(MAJOR.values())}
wd_by = {}
for w in wd:
    for a in w['alt']:
        if a: wd_by.setdefault(a, w)
out, used, kept_cur, took_wd = [], set(), 0, 0
CLUB_EN = {'Hamburgo':'Hamburg','Colonia':'Cologne','Burdeos':'Bordeaux','Niza':'Nice','Basilea':'Basel','Salzburgo':'Salzburg','Estrella Roja':'Red Star Belgrade','Spartak Moscú':'Spartak Moscow','CSKA Moscú':'CSKA Moscow','Lokomotiv Moscú':'Lokomotiv Moscow','Standard Lieja':'Standard Liège','Club Brujas':'Club Brugge','Rubin Kazán':'Rubin Kazan','Núremberg':'Nuremberg','CSKA Sofía':'CSKA Sofia','Dinamo Kiev':'Dynamo Kyiv','Al-Ahli Dubái':'Al-Ahli Dubai'}
for c in cur:
    c['st'] = [[CLUB_EN.get(x[0], x[0]), x[1], x[2]] for x in c['st']]
    w = wd_by.get(norm(c['name']))
    if w and id(w) not in used and majors(c['st']) <= majors(w['st']) and len(w['st']) >= 1:
        used.add(id(w)); out.append({**w, 'name': c['name'], 'nat': c['nat'] or w['nat']}); took_wd += 1
    else:
        if w: used.add(id(w))
        extra = {f: w.get(f) for f in ('la', 'lg', 'caps', 'ig', 'pos', 'by')} if w else {}
        if w and set(majors(c['st'])) != set(majors(w['st'])): extra['la'] = extra['lg'] = None   # trayectoria distinta: no fiarse de los totales
        out.append({'name': c['name'], 'nat': c['nat'], 'pop': w['pop'] if w else 60, 'st': c['st'], 'cur': c['st'][-1][2] >= NOW, **extra}); kept_cur += 1
for w in sorted(wd, key=lambda x: -x['pop']):
    if id(w) in used: continue
    out.append(w)
# nombres repetidos: añadir el país
groups = collections.defaultdict(list)
for o in out: groups[o['name']].append(o)
for n, g in groups.items():
    if len(g) > 1:
        for o in sorted(g, key=lambda x: -x['pop'])[1:]: o['name'] = f"{o['name']} ({o['nat']})"
cnt = collections.Counter(o['name'] for o in out)
seen = set(); final = []
for o in out:
    if o['name'] in seen: continue
    seen.add(o['name']); final.append(o)
lines = []
for o in final:
    name = o['name'].replace('|', ' ').replace('`', "'").replace('\\', '')
    sts = ';'.join(f"{x[0].replace(';',' ').replace('|',' ').replace(':',' ').replace('`', '')}:{x[1]}-{x[2]}" for x in o['st'])
    ex = [o.get('la'), o.get('lg'), o.get('caps'), o.get('ig'), o.get('pos'), 1 if o.get('cur') else 0, o.get('by')]
    lines.append(f"{name}|{o['nat']}|{sts}|{o['pop']}|" + ','.join('' if v is None else str(v) for v in ex))
with open(OUTJS, 'w', encoding='utf-8') as f:
    f.write('// Base de datos de futbolistas de Dugout.\n// Fuente: Wikidata (CC0) combinada con la base revisada a mano del prototipo.\n// Formato: nombre|país|CLUB:inicio-fin;...|popularidad|partidosLiga,golesLiga,partidosSelección,golesSelección,posición,actual,añoNacimiento\n')
    f.write('window.DG_NATS=' + json.dumps(nats, ensure_ascii=False) + ';\n')
    f.write('window.DG_PLAYERS=' + json.dumps('\n'.join(lines), ensure_ascii=False) + ';\n')
print('curados', len(cur), 'con datos de wikidata', took_wd, 'curados mantenidos', kept_cur, 'total', len(final), 'paises', len(nats))
