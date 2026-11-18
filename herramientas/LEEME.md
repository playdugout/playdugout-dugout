# Actualizar la base de datos de futbolistas

Los datos vienen de **Wikidata** (licencia CC0, uso comercial permitido) y se combinan con la
base revisada a mano del prototipo (`prototipo-claude.html`).

```bash
mkdir -p datos && python3 herramientas/fetch_wd.py datos 3100   # necesita datos/top.csv y datos/current_u.csv
python3 herramientas/fetch_stats.py datos/raw.json               # partidos y goles por club
python3 herramientas/build_players.py datos/raw.json prototipo-claude.html js/players.js /dev/null
```

Después hay que regenerar `supabase/02_cartas.sql` con `node herramientas/export_cartas.js` (necesita Playwright) y ejecutarlo en Supabase (SQL Editor) para que
el catálogo de cromos coincida con los jugadores.

Limpieza que se aplica: se quitan selecciones nacionales, filiales, equipos juveniles y de cantera
(etapas antes de los 17 años), fútbol femenino (por ahora) y jugadores sin fechas.

## Filtro de ligas
`build_players.py` lee `team_country.json` (país de cada club, sacado de Wikidata con la propiedad P17) junto a `raw.json`.
Solo entran jugadores que hayan jugado en un club grande o en España, Reino Unido, Italia, Alemania, Francia, Portugal, Países Bajos, Bélgica o Turquía, salvo leyendas muy conocidas (`KEEP_ANYWAY`) o los de la lista revisada a mano.
