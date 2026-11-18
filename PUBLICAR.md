# Cómo publicar Dugout (Netlify, gratis)

## 1. Base de datos (una sola vez)
Sigue `supabase/LEEME.md`: ejecutar `01_esquema.sql` y `02_cartas.sql` en el SQL Editor
y activar **Allow anonymous sign-ins** en Authentication → Sign In / Providers.

## 2. Publicar la web
1. Entra en https://app.netlify.com y crea la cuenta con **Sign up with GitHub** (cuenta `playdugout`).
2. **Add new site → Import an existing project → GitHub**.
3. Autoriza a Netlify y elige el repositorio **playdugout-dugout**.
4. Deja todo como viene (no hay que compilar nada; `netlify.toml` ya lo configura) y pulsa **Deploy**.
5. En un minuto tendrás la web en una dirección del tipo `https://nombre-aleatorio.netlify.app`.
   En **Site configuration → Change site name** puedes ponerle `playdugout` → `https://playdugout.netlify.app`.

Cada vez que se suban cambios al repositorio, Netlify publica la nueva versión solo.

## 3. Dominio propio (cuando lo compres)
Netlify → **Domain management → Add a domain** y sigue los pasos (te dice qué registros DNS poner).
El certificado HTTPS es automático y gratis.

## 4. Supabase: permitir tu dirección
Supabase → **Authentication → URL Configuration → Site URL**: pon la dirección de Netlify
(y más adelante tu dominio). Hace falta para cuando los jugadores vinculen su email.
