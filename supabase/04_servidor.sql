-- =====================================================================
-- Dugout · 04 · Conectar la web con el servidor
-- Ejecutar DESPUÉS de 01 y 03, y ANTES del nuevo 02_cartas.sql.
-- Se puede ejecutar varias veces sin romper nada.
--
-- Qué añade:
--  · get_my_state(): todo lo del jugador en una sola llamada (sobres, cromos, racha…)
--  · Cromos "activos": los jugadores retirados de la base ya no salen en sobres
--  · claim_daily(): admite los juegos nuevos (Who Said It?, Deep Cut)
--  · unlock_trophy(): el servidor comprueba los trofeos que puede comprobar
--  · Intercambios con un amigo concreto (nadie más puede quedarse la oferta)
--  · delete_my_account(): borrar la cuenta y todos sus datos (derecho de supresión, RGPD)
-- =====================================================================

alter table public.cards add column if not exists active boolean not null default true;
alter table public.trade_offers add column if not exists for_user uuid references public.profiles (id) on delete cascade;
create index if not exists trade_offers_for_idx on public.trade_offers (for_user);
-- Si se borra la cuenta de quien aceptó un intercambio, la oferta se queda sin "taker" en vez de bloquear el borrado
alter table public.trade_offers drop constraint if exists trade_offers_taker_fkey;
alter table public.trade_offers add constraint trade_offers_taker_fkey foreign key (taker) references public.profiles (id) on delete set null;
drop policy if exists "leer mis ofertas" on public.trade_offers;
create policy "leer mis ofertas" on public.trade_offers for select to authenticated
  using (user_id = (select auth.uid()) or taker = (select auth.uid()) or for_user = (select auth.uid()));

-- Solo se sortean cromos activos
create or replace function public.dg_random_card(p_rarity text) returns int
language sql volatile security definer set search_path = public as $$
  select id from cards where rarity = p_rarity and active order by random() limit 1
$$;

-- Reto diario completado: 1 sobre por juego y día, y actualiza la racha
create or replace function public.claim_daily(p_game text, p_level text, p_score jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_today date := dg_today(); v_n int; v_new boolean; v_p profiles%rowtype; v_gap int;
begin
  if v_uid is null then raise exception 'Sin sesión'; end if;
  if p_game not in ('link', 'grid', 'tray', 'odd', 'tl', 'lu', 'five', 'who', 'deep') then raise exception 'Juego desconocido'; end if;
  if coalesce(p_level, 'mid') not in ('easy', 'mid', 'hard') then raise exception 'Nivel desconocido'; end if;
  if p_score is not null and pg_column_size(p_score) > 2000 then raise exception 'Resultado demasiado grande'; end if;
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
  return jsonb_build_object('new', v_new, 'packs', v_p.packs, 'streak', v_p.streak, 'freezes', v_p.freezes, 'streak_best', v_p.streak_best);
end $$;

-- Trofeo desbloqueado: +1 sobre (una vez por trofeo).
-- Los que se pueden comprobar con datos del servidor se comprueban; los de rendimiento
-- en una partida (cadena perfecta, Grid completo…) se aceptan tal cual: como mucho dan 1 sobre cada uno.
create or replace function public.unlock_trophy(p_trophy text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_p profiles%rowtype; v_ok boolean; v_n int;
begin
  if v_uid is null then raise exception 'Sin sesión'; end if;
  if p_trophy not in ('first','str3','str7','str30','link','grid','lineup','five','tl','sv10','sv25','hl10',
                      'col25','col75','col177','legend','spin','trade','rkwin','rkgold','rkdia') then
    raise exception 'Trofeo desconocido';
  end if;
  select * into v_p from profiles where id = v_uid;
  v_ok := case p_trophy
    when 'first'  then exists (select 1 from daily_results where user_id = v_uid)
    when 'str3'   then v_p.streak_best >= 3
    when 'str7'   then v_p.streak_best >= 7
    when 'str30'  then v_p.streak_best >= 30
    when 'col25'  then (select count(*) from collection where user_id = v_uid and qty > 0) >= 25
    when 'col75'  then (select count(*) from collection where user_id = v_uid and qty > 0) >= 75
    when 'col177' then (select count(*) from collection c join cards k on k.id = c.card_id where c.user_id = v_uid and c.qty > 0 and k.active)
                       >= (select count(*) from cards where active)
    when 'legend' then exists (select 1 from collection c join cards k on k.id = c.card_id where c.user_id = v_uid and c.qty > 0 and k.rarity = 'legend')
    when 'spin'   then exists (select 1 from spins where user_id = v_uid)
    when 'trade'  then exists (select 1 from trade_offers where status = 'done' and (user_id = v_uid or taker = v_uid))
    when 'rkwin'  then v_p.wins >= 1
    when 'rkgold' then v_p.elo_best >= 1100
    when 'rkdia'  then v_p.elo_best >= 1500
    else true
  end;
  if not v_ok then return false; end if;
  insert into trophies (user_id, trophy) values (v_uid, p_trophy) on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n > 0 then update profiles set packs = packs + 1 where id = v_uid; end if;
  return v_n > 0;
end $$;

-- Todo el estado del jugador en una llamada
create or replace function public.get_my_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_today date := dg_today();
begin
  if v_uid is null then raise exception 'Sin sesión'; end if;
  return jsonb_build_object(
    'today',      v_today,
    'profile',    (select to_jsonb(p) - 'id' from profiles p where p.id = v_uid),
    'collection', coalesce((select jsonb_agg(jsonb_build_array(card_id, qty)) from collection where user_id = v_uid and qty > 0), '[]'::jsonb),
    'trophies',   coalesce((select jsonb_agg(trophy) from trophies where user_id = v_uid), '[]'::jsonb),
    'spun_today', exists (select 1 from spins where user_id = v_uid and day = v_today),
    'spun_ever',  exists (select 1 from spins where user_id = v_uid),
    'days',       coalesce((select jsonb_agg(distinct day) from daily_results where user_id = v_uid and day >= v_today - 40), '[]'::jsonb),
    'claimed',    coalesce((select jsonb_agg(game) from daily_results where user_id = v_uid and day = v_today), '[]'::jsonb),
    'trades',     (select count(*) from trade_offers where status = 'done' and (user_id = v_uid or taker = v_uid))
  );
end $$;

-- ---------- Intercambios ----------
-- Oferta opcionalmente reservada a un jugador concreto (intercambio con un amigo)
drop function if exists public.create_offer(int, int);
create or replace function public.create_offer(p_give int, p_want int, p_for uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'Sin sesión'; end if;
  if p_give = p_want then raise exception 'Ofreces y pides el mismo cromo'; end if;
  if p_for = v_uid then raise exception 'No puedes intercambiar contigo mismo'; end if;
  if not exists (select 1 from collection where user_id = v_uid and card_id = p_give and qty >= 1) then
    raise exception 'No tienes ese cromo'; end if;
  if not exists (select 1 from cards where id = p_want and active) then raise exception 'Ese cromo no existe'; end if;
  if (select count(*) from trade_offers where user_id = v_uid and status = 'open') >= 5 then
    raise exception 'Máximo 5 ofertas abiertas'; end if;
  insert into trade_offers (user_id, give_card, want_card, for_user) values (v_uid, p_give, p_want, p_for) returning id into v_id;
  return v_id;
end $$;

create or replace function public.accept_offer(p_offer uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); o trade_offers%rowtype;
begin
  if v_uid is null then raise exception 'Sin sesión'; end if;
  select * into o from trade_offers where id = p_offer for update;
  if not found or o.status <> 'open' then raise exception 'La oferta ya no está disponible'; end if;
  if o.user_id = v_uid then raise exception 'No puedes aceptar tu propia oferta'; end if;
  if o.for_user is not null and o.for_user <> v_uid then raise exception 'Esta oferta es para otro jugador'; end if;
  update collection set qty = qty - 1 where user_id = o.user_id and card_id = o.give_card and qty >= 1;
  if not found then update trade_offers set status = 'cancelled' where id = o.id; raise exception 'El otro jugador ya no tiene ese cromo'; end if;
  update collection set qty = qty - 1 where user_id = v_uid and card_id = o.want_card and qty >= 1;
  if not found then raise exception 'No tienes el cromo que piden'; end if;
  perform dg_add_card(v_uid, o.give_card);
  perform dg_add_card(o.user_id, o.want_card);
  update trade_offers set status = 'done', taker = v_uid, done_at = now() where id = o.id;
end $$;

-- El mercado público no enseña las ofertas reservadas a un amigo
create or replace function public.list_offers(p_card int default null)
returns table (id uuid, nick text, give_card int, want_card int, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select o.id, p.nick, o.give_card, o.want_card, o.created_at
  from trade_offers o join profiles p on p.id = o.user_id
  where o.status = 'open' and o.for_user is null and (p_card is null or o.give_card = p_card or o.want_card = p_card)
  order by o.created_at desc limit 100
$$;

-- ---------- Ranked ----------
create or replace function public.start_match(p_opponent uuid, p_seed bigint) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sin sesión'; end if;
  if p_opponent = auth.uid() or not exists (select 1 from profiles where id = p_opponent) then raise exception 'Rival no válido'; end if;
  if (select count(*) from matches where p1 = auth.uid() and created_at > now() - interval '1 minute') >= 5 then
    raise exception 'Demasiadas partidas seguidas'; end if;
  insert into matches (p1, p2, seed) values (auth.uid(), p_opponent, p_seed) returning id into v_id;
  return v_id;
end $$;

-- Enviar la puntuación. Si la partida ya terminó, devuelve el resultado (para quien acabó primero)
create or replace function public.report_score(p_match uuid, p_score int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m matches%rowtype;
begin
  if p_score not between 0 and 2000 then raise exception 'Puntuación no válida'; end if;
  select * into m from matches where id = p_match and auth.uid() in (p1, p2) and joined for update;
  if not found then raise exception 'Partida no disponible'; end if;
  if m.status = 'playing' then
    if auth.uid() = m.p1 and m.s1 is null then update matches set s1 = p_score where id = p_match;
    elsif auth.uid() = m.p2 and m.s2 is null then update matches set s2 = p_score where id = p_match; end if;
    select * into m from matches where id = p_match;
    if m.s1 is not null and m.s2 is not null then perform dg_finish_match(p_match); end if;
    select * into m from matches where id = p_match;
  end if;
  return jsonb_build_object('status', m.status, 'delta', case when auth.uid() = m.p1 then m.d1 else m.d2 end);
end $$;

-- ---------- Borrar mi cuenta (RGPD) ----------
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Sin sesión'; end if;
  update trade_offers set taker = null where taker = v_uid;
  delete from auth.users where id = v_uid;          -- en cascada: perfil, cromos, retos, trofeos, partidas…
end $$;

-- ---------- Permisos ----------
revoke execute on function public.get_my_state()                    from public, anon;
revoke execute on function public.create_offer(int, int, uuid)      from public, anon;
revoke execute on function public.delete_my_account()               from public, anon;
revoke execute on function public.dg_random_card(text)              from public, anon, authenticated;
grant execute on function public.get_my_state()                     to authenticated;
grant execute on function public.create_offer(int, int, uuid)       to authenticated;
grant execute on function public.delete_my_account()                to authenticated;
grant execute on function public.claim_daily(text, text, jsonb)     to authenticated;
grant execute on function public.unlock_trophy(text)                to authenticated;
grant execute on function public.accept_offer(uuid)                 to authenticated;
grant execute on function public.list_offers(int)                   to anon, authenticated;
grant execute on function public.start_match(uuid, bigint)          to authenticated;
grant execute on function public.report_score(uuid, int)             to authenticated;
