-- =====================================================================
-- Dugout · estructura de la base de datos (Supabase / PostgreSQL)
-- Pegar entero en Supabase → SQL Editor → New query → Run.
-- Se puede ejecutar varias veces sin romper nada.
--
-- Principio de seguridad: los jugadores solo LEEN sus propios datos.
-- Todo lo que da premios (sobres, cromos, ELO, intercambios) pasa por
-- funciones del servidor que comprueban las reglas, así nadie puede
-- darse sobres o ELO modificando la web.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Tablas ----------------------------------------------------

create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  nick        text not null default 'Player' check (char_length(nick) between 2 and 20),
  created_at  timestamptz not null default now(),
  packs       int  not null default 2 check (packs >= 0),          -- sobres sin abrir (2 de bienvenida)
  freezes     int  not null default 0 check (freezes between 0 and 2),
  streak      int  not null default 0,
  streak_best int  not null default 0,
  last_played date,
  elo         int  not null default 1000,
  elo_best    int  not null default 1000,
  wins        int  not null default 0,
  losses      int  not null default 0,
  draws       int  not null default 0
);

create table if not exists public.cards (
  id     int  primary key,
  name   text not null,
  rarity text not null check (rarity in ('common', 'rare', 'epic', 'legend'))
);

create table if not exists public.collection (
  user_id uuid not null references public.profiles (id) on delete cascade,
  card_id int  not null references public.cards (id),
  qty     int  not null default 0 check (qty >= 0),
  primary key (user_id, card_id)
);

create table if not exists public.daily_results (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  day        date not null,
  game       text not null,
  level      text not null default 'mid',
  score      jsonb,
  created_at timestamptz not null default now(),
  primary key (user_id, day, game)
);

create table if not exists public.trophies (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  trophy      text not null,
  unlocked_at timestamptz not null default now(),
  primary key (user_id, trophy)
);

create table if not exists public.spins (
  user_id uuid not null references public.profiles (id) on delete cascade,
  day     date not null,
  prize   text not null,
  card_id int,
  primary key (user_id, day)
);

create table if not exists public.trade_offers (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  give_card  int  not null references public.cards (id),
  want_card  int  not null references public.cards (id),
  status     text not null default 'open' check (status in ('open', 'done', 'cancelled')),
  taker      uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  done_at    timestamptz
);
create index if not exists trade_offers_open on public.trade_offers (status, give_card, want_card);
create index if not exists collection_card_idx     on public.collection (card_id);
create index if not exists trade_offers_user_idx   on public.trade_offers (user_id);
create index if not exists trade_offers_taker_idx  on public.trade_offers (taker);
create index if not exists trade_offers_give_idx   on public.trade_offers (give_card);
create index if not exists trade_offers_want_idx   on public.trade_offers (want_card);

create table if not exists public.matches (
  id          uuid primary key default gen_random_uuid(),
  p1          uuid not null references public.profiles (id) on delete cascade,
  p2          uuid not null references public.profiles (id) on delete cascade,
  seed        bigint not null,
  joined      boolean not null default false,   -- el rival aceptó la partida
  s1          int,
  s2          int,
  d1          int,                               -- cambio de ELO de cada jugador
  d2          int,
  status      text not null default 'playing' check (status in ('playing', 'done')),
  created_at  timestamptz not null default now(),
  finished_at timestamptz,
  check (p1 <> p2)
);
create index if not exists matches_p1_idx on public.matches (p1);
create index if not exists matches_p2_idx on public.matches (p2);

-- ---------- Seguridad por filas (RLS) --------------------------------

alter table public.profiles      enable row level security;
alter table public.cards         enable row level security;
alter table public.collection    enable row level security;
alter table public.daily_results enable row level security;
alter table public.trophies      enable row level security;
alter table public.spins         enable row level security;
alter table public.trade_offers  enable row level security;
alter table public.matches       enable row level security;

drop policy if exists "leer mi perfil"        on public.profiles;
drop policy if exists "leer cartas"           on public.cards;
drop policy if exists "leer mi coleccion"     on public.collection;
drop policy if exists "leer mis retos"        on public.daily_results;
drop policy if exists "leer mis trofeos"      on public.trophies;
drop policy if exists "leer mis tiradas"      on public.spins;
drop policy if exists "leer mis ofertas"      on public.trade_offers;
drop policy if exists "leer mis partidas"     on public.matches;

create policy "leer mi perfil"    on public.profiles      for select to authenticated using (id = (select auth.uid()));
create policy "leer cartas"       on public.cards         for select to anon, authenticated using (true);
create policy "leer mi coleccion" on public.collection    for select to authenticated using (user_id = (select auth.uid()));
create policy "leer mis retos"    on public.daily_results for select to authenticated using (user_id = (select auth.uid()));
create policy "leer mis trofeos"  on public.trophies      for select to authenticated using (user_id = (select auth.uid()));
create policy "leer mis tiradas"  on public.spins         for select to authenticated using (user_id = (select auth.uid()));
create policy "leer mis ofertas"  on public.trade_offers  for select to authenticated using (user_id = (select auth.uid()) or taker = (select auth.uid()));
create policy "leer mis partidas" on public.matches       for select to authenticated using ((select auth.uid()) in (p1, p2));
-- No hay políticas de INSERT/UPDATE/DELETE: solo las funciones de abajo escriben.

-- ---------- Utilidades ------------------------------------------------

create or replace function public.dg_today() returns date
language sql stable set search_path = public as $$ select (now() at time zone 'Europe/Madrid')::date $$;

create or replace function public.dg_add_card(p_user uuid, p_card int) returns int
language plpgsql security definer set search_path = public as $$
declare v_qty int;
begin
  insert into collection (user_id, card_id, qty) values (p_user, p_card, 1)
  on conflict (user_id, card_id) do update set qty = collection.qty + 1
  returning qty into v_qty;
  return v_qty;
end $$;

create or replace function public.dg_random_card(p_rarity text) returns int
language sql volatile security definer set search_path = public as $$
  select id from cards where rarity = p_rarity order by random() limit 1
$$;

-- Perfil automático al crear una cuenta (también las anónimas)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, nick)
  values (new.id, coalesce(nullif(left(new.raw_user_meta_data ->> 'nick', 20), ''), 'Player' || floor(random() * 9000 + 1000)::int))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Funciones que llama la web --------------------------------

-- Cambiar apodo
create or replace function public.set_nick(p_nick text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if char_length(trim(p_nick)) not between 2 and 20 then raise exception 'El apodo debe tener entre 2 y 20 caracteres'; end if;
  update profiles set nick = trim(p_nick) where id = auth.uid();
end $$;

-- Reto diario completado: 1 sobre por juego y día, y actualiza la racha
create or replace function public.claim_daily(p_game text, p_level text, p_score jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_today date := dg_today(); v_n int; v_new boolean; v_p profiles%rowtype; v_gap int;
begin
  if v_uid is null then raise exception 'Sin sesión'; end if;
  if p_game not in ('link', 'grid', 'tray', 'odd', 'tl', 'lu', 'five') then raise exception 'Juego desconocido'; end if;
  insert into daily_results (user_id, day, game, level, score) values (v_uid, v_today, p_game, coalesce(p_level, 'mid'), p_score)
  on conflict do nothing;
  get diagnostics v_n = row_count; v_new := v_n > 0;
  select * into v_p from profiles where id = v_uid for update;
  if v_new then
    v_p.packs := v_p.packs + 1;
    if v_p.last_played is null then v_p.streak := 1;
    elsif v_p.last_played = v_today then null;
    elsif v_p.last_played = v_today - 1 then v_p.streak := v_p.streak + 1;
    else
      v_gap := v_today - v_p.last_played - 1;
      if v_gap <= v_p.freezes then v_p.freezes := v_p.freezes - v_gap; v_p.streak := v_p.streak + 1;
      else v_p.streak := 1; end if;
    end if;
    v_p.last_played := v_today;
    v_p.streak_best := greatest(v_p.streak_best, v_p.streak);
    update profiles set packs = v_p.packs, streak = v_p.streak, streak_best = v_p.streak_best,
      last_played = v_p.last_played, freezes = v_p.freezes where id = v_uid;
  end if;
  return jsonb_build_object('new', v_new, 'packs', v_p.packs, 'streak', v_p.streak, 'freezes', v_p.freezes);
end $$;

-- Abrir un sobre: 3 cromos sorteados en el servidor
create or replace function public.open_pack()
returns table (out_card int, out_rarity text, out_qty int)
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_r float; v_rar text; v_card int; i int;
begin
  update profiles set packs = packs - 1 where id = v_uid and packs > 0;
  if not found then raise exception 'No tienes sobres'; end if;
  for i in 1..3 loop
    v_r := random();
    v_rar := case when v_r < 0.04 then 'legend' when v_r < 0.20 then 'epic' when v_r < 0.50 then 'rare' else 'common' end;
    v_card := dg_random_card(v_rar);
    out_card := v_card; out_rarity := v_rar; out_qty := dg_add_card(v_uid, v_card);
    return next;
  end loop;
end $$;

-- Ruleta: una tirada gratis al día
create or replace function public.spin() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_x float := random() * 100; v_prize text; v_card int; v_fz int;
begin
  if v_uid is null then raise exception 'Sin sesión'; end if;
  v_prize := case
    when v_x < 28 then 'p1' when v_x < 43 then 'fz' when v_x < 59 then 'rare' when v_x < 68 then 'p2'
    when v_x < 87 then 'none' when v_x < 96 then 'epic' when v_x < 98 then 'p3' else 'legend' end;
  if exists (select 1 from spins where user_id = v_uid and day = dg_today()) then raise exception 'Ya has girado la ruleta hoy'; end if;
  insert into spins (user_id, day, prize) values (v_uid, dg_today(), v_prize);
  if v_prize in ('p1', 'p2', 'p3') then
    update profiles set packs = packs + substr(v_prize, 2)::int where id = v_uid;
  elsif v_prize = 'fz' then
    select freezes into v_fz from profiles where id = v_uid;
    if v_fz < 2 then update profiles set freezes = freezes + 1 where id = v_uid;
    else update profiles set packs = packs + 1 where id = v_uid; v_prize := 'fz_full'; end if;
  elsif v_prize in ('rare', 'epic', 'legend') then
    v_card := dg_random_card(v_prize);
    perform dg_add_card(v_uid, v_card);
    update spins set card_id = v_card where user_id = v_uid and day = dg_today();
  end if;
  return jsonb_build_object('prize', v_prize, 'card', v_card);
end $$;

-- Trofeo desbloqueado: +1 sobre (solo una vez por trofeo)
create or replace function public.unlock_trophy(p_trophy text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if p_trophy not in ('first','str3','str7','str30','link','grid','lineup','five','tl','sv10','sv25','hl10',
                      'col25','col75','col177','legend','spin','trade','rkwin','rkgold','rkdia') then
    raise exception 'Trofeo desconocido';
  end if;
  insert into trophies (user_id, trophy) values (auth.uid(), p_trophy) on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n > 0 then update profiles set packs = packs + 1 where id = auth.uid(); end if;
  return v_n > 0;
end $$;

-- ---------- Mercado de cromos ----------------------------------------

create or replace function public.create_offer(p_give int, p_want int) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if p_give = p_want then raise exception 'Ofreces y pides el mismo cromo'; end if;
  if not exists (select 1 from collection where user_id = v_uid and card_id = p_give and qty >= 1) then
    raise exception 'No tienes ese cromo'; end if;
  if (select count(*) from trade_offers where user_id = v_uid and status = 'open') >= 5 then
    raise exception 'Máximo 5 ofertas abiertas'; end if;
  insert into trade_offers (user_id, give_card, want_card) values (v_uid, p_give, p_want) returning id into v_id;
  return v_id;
end $$;

create or replace function public.cancel_offer(p_offer uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update trade_offers set status = 'cancelled' where id = p_offer and user_id = auth.uid() and status = 'open';
end $$;

-- Aceptar una oferta: intercambio atómico comprobado en el servidor
create or replace function public.accept_offer(p_offer uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); o trade_offers%rowtype;
begin
  select * into o from trade_offers where id = p_offer for update;
  if not found or o.status <> 'open' then raise exception 'La oferta ya no está disponible'; end if;
  if o.user_id = v_uid then raise exception 'No puedes aceptar tu propia oferta'; end if;
  update collection set qty = qty - 1 where user_id = o.user_id and card_id = o.give_card and qty >= 1;
  if not found then update trade_offers set status = 'cancelled' where id = o.id; raise exception 'El otro jugador ya no tiene ese cromo'; end if;
  update collection set qty = qty - 1 where user_id = v_uid and card_id = o.want_card and qty >= 1;
  if not found then raise exception 'No tienes el cromo que piden'; end if;
  perform dg_add_card(v_uid, o.give_card);
  perform dg_add_card(o.user_id, o.want_card);
  update trade_offers set status = 'done', taker = v_uid, done_at = now() where id = o.id;
end $$;

-- Listado público del mercado (sin datos personales: solo apodo)
create or replace function public.list_offers(p_card int default null)
returns table (id uuid, nick text, give_card int, want_card int, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select o.id, p.nick, o.give_card, o.want_card, o.created_at
  from trade_offers o join profiles p on p.id = o.user_id
  where o.status = 'open' and (p_card is null or o.give_card = p_card or o.want_card = p_card)
  order by o.created_at desc limit 100
$$;

-- ---------- Ranked ----------------------------------------------------

create or replace function public.start_match(p_opponent uuid, p_seed bigint) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_opponent = auth.uid() then raise exception 'Rival no válido'; end if;
  insert into matches (p1, p2, seed) values (auth.uid(), p_opponent, p_seed) returning id into v_id;
  return v_id;
end $$;

create or replace function public.join_match(p_match uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_seed bigint;
begin
  update matches set joined = true where id = p_match and p2 = auth.uid() and status = 'playing'
    and created_at > now() - interval '5 minutes'
  returning seed into v_seed;
  if v_seed is null then raise exception 'Partida no disponible'; end if;
  return v_seed;
end $$;

-- Calcula el ELO al terminar (interna, no se puede llamar desde la web)
create or replace function public.dg_finish_match(p_match uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m matches%rowtype; e1 int; e2 int; r1 float; ex float; k int := 32; dd int;
begin
  select * into m from matches where id = p_match for update;
  if m.status = 'done' then return; end if;
  select elo into e1 from profiles where id = m.p1;
  select elo into e2 from profiles where id = m.p2;
  r1 := case when coalesce(m.s1, -1) > coalesce(m.s2, -1) then 1 when coalesce(m.s1, -1) < coalesce(m.s2, -1) then 0 else 0.5 end;
  ex := 1 / (1 + power(10, (e2 - e1) / 400.0));
  dd := round(k * (r1 - ex));
  update profiles set elo = greatest(0, elo + dd), elo_best = greatest(elo_best, elo + dd),
    wins = wins + (r1 = 1)::int, losses = losses + (r1 = 0)::int, draws = draws + (r1 = 0.5)::int where id = m.p1;
  update profiles set elo = greatest(0, elo - dd), elo_best = greatest(elo_best, elo - dd),
    wins = wins + (r1 = 0)::int, losses = losses + (r1 = 1)::int, draws = draws + (r1 = 0.5)::int where id = m.p2;
  update matches set status = 'done', d1 = dd, d2 = -dd, finished_at = now() where id = p_match;
end $$;

create or replace function public.report_score(p_match uuid, p_score int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m matches%rowtype;
begin
  if p_score not between 0 and 2000 then raise exception 'Puntuación no válida'; end if;
  select * into m from matches where id = p_match and auth.uid() in (p1, p2) and status = 'playing' and joined for update;
  if not found then raise exception 'Partida no disponible'; end if;
  if auth.uid() = m.p1 and m.s1 is null then update matches set s1 = p_score where id = p_match;
  elsif auth.uid() = m.p2 and m.s2 is null then update matches set s2 = p_score where id = p_match; end if;
  select * into m from matches where id = p_match;
  if m.s1 is not null and m.s2 is not null then perform dg_finish_match(p_match); end if;
  select * into m from matches where id = p_match;
  return jsonb_build_object('status', m.status, 'delta', case when auth.uid() = m.p1 then m.d1 else m.d2 end);
end $$;

-- Si el rival abandona: pasados 5 minutos, quien sí terminó puede cerrar la partida
create or replace function public.claim_timeout(p_match uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m matches%rowtype;
begin
  select * into m from matches where id = p_match and auth.uid() in (p1, p2) and status = 'playing' and joined;
  if not found then raise exception 'Partida no disponible'; end if;
  if m.created_at > now() - interval '5 minutes' then raise exception 'Todavía no'; end if;
  if (auth.uid() = m.p1 and m.s1 is null) or (auth.uid() = m.p2 and m.s2 is null) then raise exception 'Primero termina tu partida'; end if;
  perform dg_finish_match(p_match);
  select * into m from matches where id = p_match;
  return jsonb_build_object('status', m.status, 'delta', case when auth.uid() = m.p1 then m.d1 else m.d2 end);
end $$;

-- Clasificación pública (solo apodo y números)
create or replace function public.get_leaderboard(p_limit int default 100)
returns table (pos bigint, nick text, elo int, wins int, losses int)
language sql stable security definer set search_path = public as $$
  select row_number() over (order by elo desc, wins desc), nick, elo, wins, losses
  from profiles where wins + losses + draws > 0
  order by elo desc, wins desc limit least(p_limit, 200)
$$;

-- ---------- Permisos ---------------------------------------------------
-- (El proyecto no da acceso automático a tablas nuevas: se concede aquí.)

grant usage on schema public to anon, authenticated;
grant select on public.cards to anon, authenticated;
grant select on public.profiles, public.collection, public.daily_results, public.trophies,
                public.spins, public.trade_offers, public.matches to authenticated;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.get_leaderboard(int)                 to anon, authenticated;
grant execute on function public.list_offers(int)                     to anon, authenticated;
grant execute on function public.set_nick(text)                       to authenticated;
grant execute on function public.claim_daily(text, text, jsonb)       to authenticated;
grant execute on function public.open_pack()                          to authenticated;
grant execute on function public.spin()                               to authenticated;
grant execute on function public.unlock_trophy(text)                  to authenticated;
grant execute on function public.create_offer(int, int)               to authenticated;
grant execute on function public.cancel_offer(uuid)                   to authenticated;
grant execute on function public.accept_offer(uuid)                   to authenticated;
grant execute on function public.start_match(uuid, bigint)            to authenticated;
grant execute on function public.join_match(uuid)                     to authenticated;
grant execute on function public.report_score(uuid, int)              to authenticated;
grant execute on function public.claim_timeout(uuid)                  to authenticated;
grant execute on function public.dg_today()                           to anon, authenticated;
