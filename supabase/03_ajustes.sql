-- =====================================================================
-- Dugout · ajustes recomendados por el Advisor de Supabase
-- Pegar en SQL Editor → New query → Run. Se puede ejecutar varias veces.
-- =====================================================================

-- 1) Seguridad: fijar el search_path de la función de fecha
create or replace function public.dg_today() returns date
language sql stable set search_path = public as $$ select (now() at time zone 'Europe/Madrid')::date $$;

-- 2) Rendimiento: evaluar auth.uid() una sola vez por consulta
drop policy if exists "leer mi perfil"    on public.profiles;
drop policy if exists "leer mi coleccion" on public.collection;
drop policy if exists "leer mis retos"    on public.daily_results;
drop policy if exists "leer mis trofeos"  on public.trophies;
drop policy if exists "leer mis tiradas"  on public.spins;
drop policy if exists "leer mis ofertas"  on public.trade_offers;
drop policy if exists "leer mis partidas" on public.matches;
create policy "leer mi perfil"    on public.profiles      for select to authenticated using (id = (select auth.uid()));
create policy "leer mi coleccion" on public.collection    for select to authenticated using (user_id = (select auth.uid()));
create policy "leer mis retos"    on public.daily_results for select to authenticated using (user_id = (select auth.uid()));
create policy "leer mis trofeos"  on public.trophies      for select to authenticated using (user_id = (select auth.uid()));
create policy "leer mis tiradas"  on public.spins         for select to authenticated using (user_id = (select auth.uid()));
create policy "leer mis ofertas"  on public.trade_offers  for select to authenticated using (user_id = (select auth.uid()) or taker = (select auth.uid()));
create policy "leer mis partidas" on public.matches       for select to authenticated using ((select auth.uid()) in (p1, p2));

-- 3) Rendimiento: índices para las claves externas
create index if not exists collection_card_idx     on public.collection (card_id);
create index if not exists trade_offers_user_idx   on public.trade_offers (user_id);
create index if not exists trade_offers_taker_idx  on public.trade_offers (taker);
create index if not exists trade_offers_give_idx   on public.trade_offers (give_card);
create index if not exists trade_offers_want_idx   on public.trade_offers (want_card);
create index if not exists matches_p1_idx          on public.matches (p1);
create index if not exists matches_p2_idx          on public.matches (p2);
