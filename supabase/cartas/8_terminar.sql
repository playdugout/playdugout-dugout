-- Cromos · paso 8 de 8: pasa el catálogo cargado a la tabla de cromos.
-- Si falta alguna parte, no cambia nada y avisa.
do $$
begin
  if (select count(*) from public.cards_new) <> 3517 then
    raise exception 'Faltan partes: hay % cromos cargados de 3517. Ejecuta los pasos 2 a 7.', (select count(*) from public.cards_new);
  end if;
  alter table public.cards add column if not exists active boolean not null default true;
  insert into public.cards (id, name, rarity, active)
    select id, name, rarity, true from public.cards_new
  on conflict (id) do update set name = excluded.name, rarity = excluded.rarity, active = true;
  update public.cards c set active = false where c.active and not exists (select 1 from public.cards_new n where n.id = c.id);
  delete from public.cards c where not c.active
    and not exists (select 1 from public.collection x where x.card_id = c.id)
    and not exists (select 1 from public.trade_offers t where t.give_card = c.id or t.want_card = c.id);
  drop table public.cards_new;
end $$;
select count(*) filter (where active) as cromos_activos from public.cards;
