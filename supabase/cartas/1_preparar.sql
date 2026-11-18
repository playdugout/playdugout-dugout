-- Cromos · paso 1 de 8: prepara una tabla temporal para cargar el catálogo por partes.
create table if not exists public.cards_new (id int primary key, name text not null, rarity text not null);
alter table public.cards_new enable row level security;
revoke all on public.cards_new from anon, authenticated;
truncate public.cards_new;
