# Dugout · base de datos en Supabase

Orden para un proyecto nuevo (Supabase → **SQL Editor** → **New query** → pegar → **Run**, uno por uno):

1. `01_esquema.sql` — tablas, seguridad y funciones básicas.
2. `03_ajustes.sql` — ajustes de seguridad y rendimiento que recomienda el Advisor.
3. `04_servidor.sql` — conecta la web con el servidor: estado del jugador, trofeos comprobados, intercambios con amigos, ranked y borrar cuenta.
4. `02_cartas.sql` — catálogo de cromos (necesita el 04 antes).
5. `05_estadisticas.sql` — estadísticas de uso (solo de quien las acepta) y buzón de opiniones.
6. **Authentication → Sign In / Providers** → activa **Allow anonymous sign-ins**.

Si ya tenías 01 y 03 ejecutados, basta con ejecutar **04** y después **02**.

Todos los archivos se pueden volver a ejecutar sin problema.

El álbum tiene una lista fija de cromos (`js/cards.js`), separada de la lista de jugadores de los juegos. Actualizar jugadores no cambia el álbum; solo si se añaden cromos a `js/cards.js` hay que regenerar y volver a ejecutar el 02.

Los números de cromo son fijos (salen del nombre del jugador), así que actualizar la lista de jugadores no estropea las colecciones.

## Ver estadísticas y opiniones
En **SQL Editor → New query**, escribe una de estas líneas y pulsa **Run**:

- `select * from stats_daily;` — jugadores y partidas por día.
- `select * from stats_games;` — juegos más jugados (30 días) y qué porcentaje se termina.
- `select * from stats_retention;` — de los jugadores nuevos de cada día, cuántos vuelven al día siguiente y a la semana.
- `select * from feedback_recent;` — últimas opiniones y avisos de errores.

Solo cuentan quienes aceptan las estadísticas en el aviso de cookies, así que los números reales serán algo mayores.
