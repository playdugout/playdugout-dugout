-- =====================================================================
-- Dugout · 05 · Estadísticas de uso y buzón de opiniones
-- Ejecutar después de 04_servidor.sql. Se puede ejecutar varias veces.
--
--  · events: qué juegos se abren y se terminan (solo si el jugador acepta las estadísticas)
--  · feedback: opiniones y avisos de errores que envía la gente desde la web
--  · vistas stats_* y feedback_recent: para que tú las consultes en el SQL Editor
--    (nadie más puede leerlas: ni la web ni los jugadores)
-- =====================================================================

create table if not exists public.events (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  name       text not null check (name in ('visit', 'view', 'finish', 'share', 'challenge')),
  game       text check (char_length(game) <= 20),
  level      text check (level in ('easy', 'mid', 'hard')),
  daily      boolean,
  result     text check (char_length(result) <= 40),
  day        date not null default public.dg_today(),
  created_at timestamptz not null default now()
);
create index if not exists events_day_idx  on public.events (day);
create index if not exists events_user_idx on public.events (user_id, day);

create table if not exists public.feedback (
  id         bigint generated always as identity primary key,
  user_id    uuid references public.profiles (id) on delete cascade,
  kind       text not null check (kind in ('bug', 'idea', 'other')),
  message    text not null check (char_length(message) between 3 and 1000),
  page       text check (char_length(page) <= 40),
  level      text,
  created_at timestamptz not null default now()
);
create index if not exists feedback_user_idx on public.feedback (user_id);

alter table public.events   enable row level security;
alter table public.feedback enable row level security;
-- Sin políticas: nadie puede leer ni escribir directamente. Solo las funciones de abajo escriben.

-- Registrar un evento (máximo 400 por jugador y día, para evitar abusos)
create or replace function public.log_event(p_name text, p_game text default null, p_level text default null,
                                            p_daily boolean default null, p_result text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then return; end if;
  if p_name not in ('visit', 'view', 'finish', 'share', 'challenge') then return; end if;
  if (select count(*) from events where user_id = v_uid and day = dg_today()) >= 400 then return; end if;
  -- 'visit' una vez al día por jugador
  if p_name = 'visit' and exists (select 1 from events where user_id = v_uid and day = dg_today() and name = 'visit') then return; end if;
  insert into events (user_id, name, game, level, daily, result)
  values (v_uid, p_name, left(p_game, 20), case when p_level in ('easy', 'mid', 'hard') then p_level end, p_daily, left(p_result, 40));
end $$;

-- Enviar una opinión (máximo 10 por jugador y día)
create or replace function public.send_feedback(p_kind text, p_message text, p_page text default null, p_level text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Sin sesión'; end if;
  if p_kind not in ('bug', 'idea', 'other') then raise exception 'Tipo no válido'; end if;
  if char_length(trim(p_message)) not between 3 and 1000 then raise exception 'El mensaje debe tener entre 3 y 1000 caracteres'; end if;
  if (select count(*) from feedback where user_id = v_uid and created_at > now() - interval '1 day') >= 10 then
    raise exception 'Has enviado muchas opiniones hoy. Gracias, ¡prueba mañana!'; end if;
  insert into feedback (user_id, kind, message, page, level) values (v_uid, p_kind, trim(p_message), left(p_page, 40), left(p_level, 10));
end $$;

-- ---------- Vistas para consultar (solo desde el panel de Supabase) ----------

-- Actividad por día: jugadores, partidas terminadas y retos diarios completados
create or replace view public.stats_daily with (security_invoker = true) as
select day,
       count(distinct user_id)                                   as players,
       count(*) filter (where name = 'finish')                   as games_finished,
       count(*) filter (where name = 'finish' and daily)         as daily_finished,
       count(*) filter (where name = 'share')                    as shares,
       count(*) filter (where name = 'challenge')                as challenges_opened
from public.events group by day order by day desc;

-- Juegos más jugados en los últimos 30 días, y cuántos de los que entran terminan
create or replace view public.stats_games with (security_invoker = true) as
select game,
       count(distinct user_id) filter (where name = 'view')     as players_opened,
       count(*) filter (where name = 'view')                     as times_opened,
       count(*) filter (where name = 'finish')                   as times_finished,
       round(100.0 * count(*) filter (where name = 'finish') / nullif(count(*) filter (where name = 'view'), 0), 1) as finish_rate_pct
from public.events where game is not null and day >= dg_today() - 30
group by game order by times_opened desc;

-- Repetición: de los que jugaron por primera vez un día, cuántos volvieron al día siguiente y a la semana
create or replace view public.stats_retention with (security_invoker = true) as
with first_day as (select user_id, min(day) as d0 from public.events group by user_id),
     active as (select distinct user_id, day from public.events)
select f.d0 as first_day,
       count(*)                                                                  as new_players,
       count(*) filter (where exists (select 1 from active a where a.user_id = f.user_id and a.day = f.d0 + 1))                    as back_next_day,
       count(*) filter (where exists (select 1 from active a where a.user_id = f.user_id and a.day between f.d0 + 6 and f.d0 + 8)) as back_after_a_week
from first_day f group by f.d0 order by f.d0 desc;

-- Últimas opiniones
create or replace view public.feedback_recent with (security_invoker = true) as
select created_at, kind, page, level, message from public.feedback order by created_at desc limit 200;

-- ---------- Permisos ----------
revoke all on public.events, public.feedback from anon, authenticated;
revoke all on public.stats_daily, public.stats_games, public.stats_retention, public.feedback_recent from anon, authenticated;
revoke execute on function public.log_event(text, text, text, boolean, text)  from public, anon;
revoke execute on function public.send_feedback(text, text, text, text)       from public, anon;
grant execute on function public.log_event(text, text, text, boolean, text)   to authenticated;
grant execute on function public.send_feedback(text, text, text, text)        to authenticated;

-- Limpieza (ejecutar de vez en cuando): borra estadísticas de hace más de 14 meses
-- delete from public.events where created_at < now() - interval '14 months';
