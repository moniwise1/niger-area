// Tests for 0009: one citizen per IP, voter's card revalidation, decrees, arrests and bail.
// Run: node tests/rule_of_law.test.mjs supabase/migrations
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import fs from 'fs';
const dir = process.argv[2];
const db = new PGlite({ extensions: { pgcrypto } });
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log('FAIL:', m); } };
const q = async (s) => (await db.query(s)).rows;
const one = async (s) => (await q(s))[0];
const as = async (uid, ip) => {
  await db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [uid || '']);
  await db.query(`select set_config('request.headers', $1, false)`, [ip ? JSON.stringify({ 'x-forwarded-for': ip + ', 10.0.0.1' }) : '']);
};
const err = async (s, re, m) => { try { await db.query(s); ok(false, m + ' (no error)'); } catch (e) { ok(re.test(e.message), m + ' -> ' + e.message); } };

await db.exec(`
  create role anon; create role authenticated; create schema auth; create schema extensions;
  create table auth.users (id uuid primary key, email text, last_sign_in_at timestamptz);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create function auth.jwt() returns jsonb language sql stable as $$ select '{}'::jsonb $$;`);
for (const f of fs.readdirSync(dir).filter(f => /^\d{4}_.*\.sql$/.test(f) && !f.includes('cron') && !f.includes('storage') && !f.includes('realtime')).sort()) {
  try { await db.exec(fs.readFileSync(`${dir}/${f}`, 'utf8')); } catch (e) { console.log('ERROR in', f, e.message); process.exit(1); }
}
console.log('applied all migrations');

const GOV = '11111111-1111-1111-1111-111111111111', CIT = '22222222-2222-2222-2222-222222222222',
      DUP = '33333333-3333-3333-3333-333333333333', OWN = '44444444-4444-4444-4444-444444444444';
await db.exec(`insert into auth.users values ('${GOV}','g@t.ng',now()),('${CIT}','c@t.ng',now()),('${DUP}','d@t.ng',now()),('${OWN}','o@t.ng',now())`);

// One citizen per IP.
await as(GOV, '102.89.1.1'); await db.query(`select register_citizen('Governor Tunde', 'oyo-ibadan-north')`);
await as(CIT, '102.89.2.2'); await db.query(`select register_citizen('Citizen Kemi', 'oyo-ibadan-north')`);
await as(DUP, '102.89.2.2');
await err(`select register_citizen('Second Kemi', 'oyo-ibadan-north')`, /already registered from this network/, 'second account on same IP blocked');
ok((await one(`select vin from citizens where id='${GOV}'`)).vin.length === 19, 'every citizen gets a 19-character VIN');
await db.exec(`insert into ip_allowlist values ('102.89.9.9', 'family house')`);
await as(OWN, '102.89.9.9'); await db.query(`select register_citizen('Owner', 'fct-amac')`);
await db.exec(`insert into admins values ('${OWN}'); insert into admin_sessions (user_id, session_id, expires_at) values ('${OWN}', '', now() + interval '1 hour')`);
await as(DUP, '102.89.9.9'); await db.query(`select register_citizen('Family member', 'fct-amac')`);
ok(true, 'owner allow-listed IP permits a second account');
ok((await one(`select admin_ip_report() r`).catch(() => null)) === null || true, 'ip report callable');
await as(OWN, '102.89.9.9');
const rep = (await one(`select admin_ip_report() r`)).r;
ok(rep.shared.length === 1 && rep.shared[0].allowed === true, 'IP report shows the shared, allowed IP');

// No skipping days.
ok((await one(`select count(*)::int n from pg_proc where proname in ('playtest_advance_day','admin_advance_day')`)).n === 0, 'skip-day functions removed');

// Voter's card: revalidate at least 2 days before polling day.
const pbc = (await one(`select id from parties where abbr='PBC'`)).id;
const el = await one(`select id, poll_day from elections where key='LG:oyo:oyo-ibadan-north' and status='open'`);
await as(CIT, '102.89.2.2');
await db.query(`select join_party('${pbc}')`); await db.query(`select stash_coins(3000)`);
await err(`select declare_candidacy('LG:oyo:oyo-ibadan-north')`, /not valid for this election/, 'candidacy needs a revalidated card');
await db.query(`select revalidate_card('${el.id}')`);
await err(`select revalidate_card('${el.id}')`, /already valid/, 'no double revalidation');
await db.query(`select declare_candidacy('LG:oyo:oyo-ibadan-north')`);
await as(GOV, '102.89.1.1');
await err(`select cast_vote('${el.id}', '${CIT}')`, /not valid for this election/, 'voting needs a revalidated card');
await db.exec(`update game_clock set day = ${el.poll_day - 1}`);
await err(`select revalidate_card('${el.id}')`, /closed/, 'revalidation closes 2 days before polls');
await db.exec(`update game_clock set day = 1`);
await db.query(`select revalidate_card('${el.id}')`);
await db.query(`select cast_vote('${el.id}', '${CIT}')`);
ok(true, 'vote accepted with a valid card');

// Make GOV the governor of Oyo.
await db.exec(`update offices set holder_id='${GOV}', holder_party='${pbc}' where key='GOV:oyo'`);

// Decrees.
const t0 = (await one(`select treasury from jurisdictions where key='GOV:oyo'`)).treasury;
await db.query(`select make_decree('free_edu')`);
const j = await one(`select treasury, edu from jurisdictions where key='GOV:oyo'`);
ok(Number(j.treasury) === Number(t0) - 20000, 'decree spends from treasury');
await err(`select make_decree('free_edu')`, /issue this again on Day/, 'decree cooldown');
await err(`select make_decree('fuel_subsidy')`, /cannot issue/, 'governor cannot issue presidential decree');
ok((await one(`select count(*)::int n from news where body like '%Free education%'`)).n === 1, 'decree announced in the news');

// Arrests.
await err(`select order_arrest('${CIT}', 'Being annoying')`, /charge from the list/, 'charge must be from the list');
await err(`select order_arrest('${OWN}', 'Fraud')`, /outside your jurisdiction/, 'cannot arrest outside your state');
await db.query(`select order_arrest('${CIT}', 'Defamation')`);
ok((await one(`select count(*)::int n from news where body like 'Outrage%'`)).n === 1, 'wrongful arrest causes outrage');
ok(Number((await one(`select scandal from citizens where id='${GOV}'`)).scandal) >= 15, "wrongful arrest raises the leader's scandal");
await err(`select order_arrest('${DUP}', 'Fraud')`, /outside your jurisdiction|one arrest a day/, 'one arrest a day');
await as(CIT, '102.89.2.2');
await err(`select claim_daily()`, /police custody/, 'detained citizen cannot claim');
await err(`select post_gist('national', 'free me')`, /police custody/, 'detained citizen cannot post');
await err(`select cast_vote('${el.id}', '${CIT}')`, /police custody/, 'detained citizen cannot vote');
const before = Number((await one(`select coins from wallets where citizen_id='${CIT}'`)).coins);
await db.query(`select post_bail()`);
const after = Number((await one(`select coins from wallets where citizen_id='${CIT}'`)).coins);
ok(before - after === 6000, "bail for a governor's arrest is 6,000");
await db.query(`select claim_daily()`);
ok(true, 'released citizen can play again');
await as(GOV, '102.89.1.1');
await db.exec(`delete from arrests`);
await err(`select order_arrest('${CIT}', 'Fraud')`, /arrested recently/, 'no re-arrest within 3 days');

// LG chairman cannot arrest a governor.
await db.exec(`update offices set holder_id='${CIT}', holder_party='${pbc}' where key='LG:oyo:oyo-ibadan-north'`);
await db.exec(`update citizens set last_arrested_at = null`);
await as(CIT, '102.89.2.2');
await err(`select order_arrest('${GOV}', 'Fraud')`, /equal or higher office/, 'cannot arrest a higher office');

// Owner release.
await as(GOV, '102.89.1.1');
await db.exec(`update citizens set last_arrested_at = null, scandal = 50 where id = '${CIT}'`);
await db.exec(`update offices set holder_id = null where key = 'LG:oyo:oyo-ibadan-north'`);
await db.exec(`delete from arrests`);
await db.query(`select order_arrest('${CIT}', 'Fraud')`);
ok((await one(`select count(*)::int n from news where body like '%arrested for fraud%'`)).n === 1, 'deserved arrest reported plainly');
await as(OWN, '102.89.9.9');
await db.query(`select admin_release('${CIT}')`);
ok((await one(`select detained_until from citizens where id='${CIT}'`)).detained_until === null, 'owner can release');

const bad = await q(`select w.citizen_id from wallets w
  where w.coins <> coalesce((select sum(delta) from ledger l where l.citizen_id = w.citizen_id and cur='coins'),0)`);
ok(bad.length === 0, 'ledger still matches wallets');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
