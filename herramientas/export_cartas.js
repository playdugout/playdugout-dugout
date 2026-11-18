const {chromium}=require('playwright');(async()=>{
const srv=require('child_process').spawn('python3',['-m','http.server','8778','-d',require('path').join(__dirname,'..')]);await new Promise(r=>setTimeout(r,800));
const b=await chromium.launch();const ctx=await b.newContext();await ctx.route('**/supabase.min.js',r=>r.fulfill({body:'',contentType:'text/javascript'}));
const p=await ctx.newPage();await p.goto('http://localhost:8778/');await p.waitForTimeout(800);
const o=await p.evaluate(()=>({rows:PLAYERS.map(x=>[x.cid,x.name,x.rar]),uniq:CID.size}));
if(o.uniq!==o.rows.length)throw new Error('collision');
const esc=s=>s.replace(/'/g,"''");
const sql=`-- Card catalogue (one per player). Generated from the game database (Wikidata + manual review).
-- Card ids are fixed (a hash of the player's name), so they don't change when the player list is updated.
-- Run 04_servidor.sql first. Safe to run again.
alter table public.cards add column if not exists active boolean not null default true;
update public.cards set active = false where active;
insert into public.cards (id, name, rarity, active) values
`+o.rows.map(r=>"  ("+r[0]+", '"+esc(r[1])+"', '"+r[2]+"', true)").join(',\n')+`
on conflict (id) do update set name = excluded.name, rarity = excluded.rarity, active = true;

-- Remove cards that are no longer in the game (unless someone owns or trades them)
delete from public.cards c where not c.active
  and not exists (select 1 from public.collection x where x.card_id = c.id)
  and not exists (select 1 from public.trade_offers t where t.give_card = c.id or t.want_card = c.id);
`;
require('fs').writeFileSync(require('path').join(__dirname,'..','supabase','02_cartas.sql'),sql);console.log(o.rows.length,'cards, unique ids',o.uniq);await b.close();srv.kill()})()
