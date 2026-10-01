import { PGlite } from '@electric-sql/pglite';
import fs from 'fs';
const dir = process.argv[2];
const db = new PGlite();
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; } else { fail++; console.log('FAIL:', m); } };
const q = async (s, p) => (await db.query(s, p)).rows;
const as = async (uid) => db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [uid || '']);
const expectErr = async (s, re, m) => { try { await db.query(s); ok(false, m + ' (no error)'); } catch (e) { ok(re.test(e.message), m + ' -> ' + e.message); } };

await db.exec(`
  create role anon; create role authenticated;
  create schema auth;
  create table auth.users (id uuid primary key);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant usage on schema public to authenticated;
`);
for (const f of ['0001_schema.sql', '0002_player_functions.sql', '0003_daily_tick.sql', '0004_seed.sql']) {
  try { await db.exec(fs.readFileSync(`${dir}/${f}`, 'utf8')); console.log('applied', f); }
  catch (e) { console.log('ERROR in', f, e.message); process.exit(1); }
}
// Mimic Supabase's default table grants so RLS is what protects the data.
await db.exec(`grant select, insert, update, delete on all tables in schema public to authenticated;`);

const A = '11111111-1111-1111-1111-111111111111', B = '22222222-2222-2222-2222-222222222222';
await db.exec(`insert into auth.users values ('${A}'), ('${B}')`);

await as(A); await db.query(`select register_citizen('Adaeze Okafor', 'lagos-ikeja')`);
await as(B); await db.query(`select register_citizen('Musa Bello', 'lagos-ikeja')`);
ok((await q(`select coins from wallets where citizen_id = '${A}'`))[0].coins == 1500, 'welcome bonus');

await as(A);
await db.query(`select claim_daily()`);
await expectErr(`select claim_daily()`, /already claimed/, 'double daily claim blocked');
ok((await q(`select coins, cp from wallets where citizen_id = '${A}'`))[0].cp == 0, 'no civic points without phone verification');

await expectErr(`select gift_coins('${B}', 100)`, /verified phone/, 'gift needs phone verification');
await db.exec(`update citizens set kyc_level = 1, created_at = now() - interval '10 days'`);
await db.query(`select gift_coins('${B}', 1500)`);
await expectErr(`select gift_coins('${B}', 600)`, /500 more coins/, 'daily gift cap');

await expectErr(`select redeem_cp(500, '+2348012345678')`, /NIN or BVN/, 'redeem needs identity verification');
await expectErr(`select stash_coins(999999)`, /Not enough coins in your wallet/, 'overspend blocked');

// Give A money to campaign, through the ledger so balances stay consistent.
await db.query(`select _move('${A}', 'coins', 200000, 'test_grant')`);
await db.query(`select stash_coins(100000)`);
await expectErr(`select declare_candidacy('LG:lagos:lagos-ikeja')`, /party ticket/, 'needs a party');
const pbc = (await q(`select id from parties where abbr = 'PBC'`))[0].id;
await db.query(`select join_party('${pbc}')`);
await expectErr(`select declare_candidacy('GOV:kano')`, /registered to vote/, 'cannot run outside home state');
await expectErr(`select declare_candidacy('SEN:lagos')`, /reputation 8/, 'reputation gate');
await db.query(`select declare_candidacy('LG:lagos:lagos-ikeja')`);

await as(B);
await db.query(`select join_party('${pbc}')`);
await db.query(`select _move('${B}', 'stash', 5000, 'test_grant')`);
await expectErr(`select declare_candidacy('LG:lagos:lagos-ikeja')`, /already has a candidate/, 'one ticket per party');

// Campaign until the spending limit bites (energy resets each day).
await as(A);
let capHit = false;
for (let i = 0; i < 40 && !capHit; i++) {
  try { await db.query(`select campaign('buy')`); }
  catch (e) {
    if (/spending limit/.test(e.message)) capHit = true;
    else if (/No energy/.test(e.message)) { await as(null); await db.query(`select advance_day()`); await as(A); }
    else { console.log('unexpected', e.message); break; }
  }
}
ok(capHit, 'spending limit enforced');
ok((await q(`select spent from candidates where citizen_id = '${A}'`))[0].spent <= 8000, 'spent within cap');

// Players cannot touch money or the clock directly.
await db.exec(`set role authenticated`);
await as(A);
const upd = await db.query(`update wallets set coins = 99999999 where citizen_id = '${A}'`);
ok(upd.affectedRows === 0, 'RLS blocks direct wallet edits');
await expectErr(`select advance_day()`, /permission denied/, 'players cannot advance the clock');
await expectErr(`select credit_purchase('x', 1)`, /permission denied/, 'players cannot credit purchases');
const seeB = await q(`select * from wallets`);
ok(seeB.length === 1, 'players only see their own wallet');
await db.exec(`reset role`);

// Run 150 days of game time.
await as(null);
for (let i = 0; i < 150; i++) {
  try { await db.query(`select advance_day()`); } catch (e) { ok(false, 'tick day ' + i + ': ' + e.message); break; }
}
const held = await q(`select o.key, c.display_name from offices o join citizens c on c.id = o.holder_id`);
console.log('offices held by players:', held.map(h => h.key + ' ' + h.display_name).join(', ') || 'none');
ok((await q(`select count(*)::int n from elections where status = 'closed'`))[0].n > 0, 'elections resolved');
ok((await q(`select count(*)::int n from elections where status = 'open'`))[0].n === (await q(`select count(*)::int n from jurisdictions`))[0].n, 'every seat has exactly one open election');

// Books must balance: wallet = sum of ledger, per currency.
const bad = await q(`
  select w.citizen_id from wallets w
   where w.coins <> coalesce((select sum(delta) from ledger l where l.citizen_id = w.citizen_id and cur = 'coins'), 0)
      or w.stash <> coalesce((select sum(delta) from ledger l where l.citizen_id = w.citizen_id and cur = 'stash'), 0)
      or w.cp    <> coalesce((select sum(delta) from ledger l where l.citizen_id = w.citizen_id and cur = 'cp'), 0)`);
ok(bad.length === 0, 'ledger matches wallets');

// Purchases credit exactly once, and a wrong amount is refused.
await db.query(`select create_purchase('${B}', 'small', 'ref-1')`);
await db.query(`select credit_purchase('ref-1', 50000)`);
await db.query(`select credit_purchase('ref-1', 50000)`);
ok((await q(`select count(*)::int n from ledger where reason = 'coin_purchase'`))[0].n === 1, 'webhook replay credits once');
await db.query(`select create_purchase('${B}', 'large', 'ref-2')`);
ok((await q(`select credit_purchase('ref-2', 100) ok`))[0].ok === false, 'underpayment refused');

// Ads: replay-safe and capped at 5 a day.
for (let i = 0; i < 7; i++) await db.query(`select credit_ad_reward('${A}', 'txn-${i}')`);
await db.query(`select credit_ad_reward('${A}', 'txn-0')`);
ok((await q(`select count(*)::int n from ledger where reason = 'rewarded_ad' and citizen_id = '${A}'`))[0].n === 5, 'ads capped at 5 and replays ignored');

console.log('A history:', JSON.stringify(await q(`select e.key, e.poll_day, c.votes from candidates c join elections e on e.id = c.election_id where c.citizen_id = '${A}'`)),
  JSON.stringify(await q(`select reason, count(*)::int n from ledger where citizen_id = '${A}' and reason in ('election_win', 'salary') group by reason`)),
  JSON.stringify(await q(`select rep, offices_held from citizens where id = '${A}'`)));
console.log(`\n${pass} passed, ${fail} failed`);
console.log('news sample:', (await q(`select day, body from news order by id desc limit 4`)).map(n => `[${n.day}] ${n.body}`).join('\n  '));
process.exit(fail ? 1 : 0);
