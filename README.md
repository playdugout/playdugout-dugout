# Dugout

Juegos diarios de fútbol: Link-Up, Grid, Career, Odd One Out, Lineup, 5-4-3-2-1, Higher or Lower,
Survival, Timeline, Versus/Ranked online, cromos, trofeos y ruleta.

- `index.html` — la web pública (todos los juegos).
- `js/online.js` — conexión con Supabase: cuenta anónima automática y salas en tiempo real (Versus, Ranked, intercambios).
- `js/config.js` — dirección y clave pública de Supabase.
- `js/players.js` — base de datos de 3.737 futbolistas con trayectorias, partidos y goles de liga, partidos con la selección y posición (Wikidata + revisión manual).
- `herramientas/` — programas para actualizar la base de datos de futbolistas.
- `PUBLICAR.md` — cómo publicarla en Netlify.
- `prototipo-claude.html` — prototipo original (versión publicada en Claude), como referencia.
- `supabase/` — base de datos (esquema con reglas de seguridad y catálogo de cromos). Ver `supabase/LEEME.md`.
- `IDEAS.md` — ideas pendientes.

## Estado
- ✅ Web independiente lista para Netlify.
- ✅ 3.737 futbolistas (de las ligas conocidas + leyendas) con trayectorias, estadísticas reales y posición.
- ✅ Modo online (Versus, Ranked, intercambio con amigos) sobre Supabase Realtime.
- ✅ Sobres, cromos, trofeos, ruleta, racha, intercambios y ELO guardados y validados en el servidor (Supabase), con modo local si no hay conexión.
- ✅ Páginas legales (`legal.html`: aviso legal, privacidad y cookies), aviso de cookies y botón «Delete my data».
  (ahora se guardan en el navegador de cada jugador).
