# Dugout · base de datos en Supabase

1. Supabase → **SQL Editor** → **New query** → pega todo `01_esquema.sql` → **Run**.
2. Otra **New query** → pega todo `02_cartas.sql` → **Run**.
3. Otra **New query** → pega `03_ajustes.sql` → **Run** (ajustes de seguridad y rendimiento que recomienda el Advisor).
4. **Authentication → Sign In / Providers** → activa **Allow anonymous sign-ins**
   (así cualquiera juega sin registrarse; luego puede vincular su email para no perder la cuenta).

Los dos archivos se pueden volver a ejecutar sin problema (por ejemplo, cuando añadamos jugadores).
