# Dugout · base de datos en Supabase

Orden para un proyecto nuevo (Supabase → **SQL Editor** → **New query** → pegar → **Run**, uno por uno):

1. `01_esquema.sql` — tablas, seguridad y funciones básicas.
2. `03_ajustes.sql` — ajustes de seguridad y rendimiento que recomienda el Advisor.
3. `04_servidor.sql` — conecta la web con el servidor: estado del jugador, trofeos comprobados, intercambios con amigos, ranked y borrar cuenta.
4. `02_cartas.sql` — catálogo de cromos (necesita el 04 antes).
5. **Authentication → Sign In / Providers** → activa **Allow anonymous sign-ins**.

Si ya tenías 01 y 03 ejecutados, basta con ejecutar **04** y después **02**.

Todos los archivos se pueden volver a ejecutar sin problema (por ejemplo, cuando actualicemos jugadores: solo hace falta el 02).

Los números de cromo son fijos (salen del nombre del jugador), así que actualizar la lista de jugadores no estropea las colecciones.
