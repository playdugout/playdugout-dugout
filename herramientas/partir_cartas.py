# Parte supabase/02_cartas.sql en pasos pequeños (supabase/cartas/) para pegarlos en el SQL Editor de Supabase,
# que no admite textos tan largos. Uso: python3 herramientas/partir_cartas.py
import re, os
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
s = open(os.path.join(ROOT, 'supabase', '02_cartas.sql'), encoding='utf-8').read()
rows = re.findall(r"^  \((\d+), '((?:[^']|'')*)', '(\w+)', true\)", s, re.M)
D = os.path.join(ROOT, 'supabase', 'cartas'); os.makedirs(D, exist_ok=True)
for f in os.listdir(D): os.remove(os.path.join(D, f))
N = 6; T = N + 2; size = (len(rows) + N - 1) // N
open(f'{D}/1_preparar.sql', 'w', encoding='utf-8').write(f'''-- Cromos · paso 1 de {T}: prepara una tabla temporal para cargar el catálogo por partes.
create table if not exists public.cards_new (id int primary key, name text not null, rarity text not null);
alter table public.cards_new enable row level security;
revoke all on public.cards_new from anon, authenticated;
truncate public.cards_new;
''')
for i in range(N):
    part = rows[i * size:(i + 1) * size]
    open(f'{D}/{i + 2}_parte{i + 1}.sql', 'w', encoding='utf-8').write(
        f'-- Cromos · paso {i + 2} de {T}: parte {i + 1} de {N} del catálogo ({len(part)} cromos).\ninsert into public.cards_new (id, name, rarity) values\n'
        + ',\n'.join(f"  ({a}, '{b}', '{c}')" for a, b, c in part) + '\non conflict (id) do update set name = excluded.name, rarity = excluded.rarity;\n')
open(f'{D}/{T}_terminar.sql', 'w', encoding='utf-8').write(f'''-- Cromos · paso {T} de {T}: pasa el catálogo cargado a la tabla de cromos.
-- Si falta alguna parte, no cambia nada y avisa.
do $$
begin
  if (select count(*) from public.cards_new) <> {len(rows)} then
    raise exception 'Faltan partes: hay % cromos cargados de {len(rows)}. Ejecuta los pasos 2 a {T - 1}.', (select count(*) from public.cards_new);
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
''')
print(len(rows), 'cromos en', T, 'pasos')
