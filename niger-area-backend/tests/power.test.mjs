// Tests for 0015: taxes, nomination fees, tenure, salaries, office history, presidential term limit.
// Run: node tests/power.test.mjs supabase/migrations
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import fs from 'fs';
process.on('unhandledRejection', e => { console.log('UNHANDLED:', e.message, '|', (e.where || '').slice(0, 300)); process.exit(1); });
const dir = process.argv[2]; const db = new PGlite({ extensions: { pgcrypto } });
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log('FAIL:', m); } };
const one = async (s) => (await db.query(s)).rows[0];
const as = (u) => db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [u || '']);
const err = async (s, re, m) => { try { await db.query(s); ok(false, m + ' (no error)'); } catch (e) { ok(re.test(e.message), m + ' -> ' + e.message); } };
await db.exec(`create role anon; create role authenticated; create schema auth; create schema extensions;
  create table auth.users (id uuid primary key, email text, last_sign_in_at timestamptz);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create function auth.jwt() returns jsonb language sql stable as $$ select '{}'::jsonb $$;`);
for (const f of fs.readdirSync(dir).filter(f => /^\d{4}_.*\.sql$/.test(f) && !/cron|storage|realtime/.test(f)).sort()) {
  try { await db.exec(fs.readFileSync(`${dir}/${f}`, 'utf8')); } catch (e) { console.log('ERROR in', f, e.message); process.exit(1); } }

const P = '11111111-1111-1111-1111-111111111111', G = '22222222-2222-2222-2222-222222222222', X = '33333333-3333-3333-3333-333333333333';
await db.exec(`insert into auth.users values ('${P}','p',now()),('${G}','g',now()),('${X}','x',now())`);
for (const [u, n] of [[P, 'President Bola'], [G, 'Governor Ngozi'], [X, 'Citizen Musa']]) { await as(u); await db.query(`select register_citizen('${n}','lagos-ikeja')`); }
const pbc = (await one(`select id from parties where abbr='PBC'`)).id;
const coins = async u => Number((await one(`select coins from wallets where citizen_id='${u}'`)).coins);
const treas = async k => Number((await one(`select treasury from jurisdictions where key='${k}'`)).treasury);

// Put P in the presidency and G in Lagos government house through the real election path.
await db.exec(`update office_rules set min_rep = 0`);
for (const [u, key] of [[P, 'PRES'], [G, 'GOV:lagos']]) {
  await as(u); await db.query(`select join_party('${pbc}')`).catch(() => {});
  await db.query(`select _move('${u}', 'stash', 50000, 'test_grant')`);
  const e = (await one(`select id from elections where key='${key}' and status='open'`)).id;
  await db.query(`select revalidate_card('${e}')`);
  await db.exec(`delete from candidates where election_id='${e}'`);
}
// PBC can field only one ticket per race; G joins a different party for the governorship.
const pup = (await one(`select id from parties where abbr='PUP'`)).id;
await as(G); await db.query(`select leave_party()`); await db.query(`select join_party('${pup}')`);
await as(P); await db.query(`select declare_candidacy('PRES')`);
await as(G); await db.query(`select declare_candidacy('GOV:lagos')`);
await db.exec(`update elections set poll_day = 2 where key in ('PRES','GOV:lagos') and status='open'`);
await as(null); await db.query(`select advance_day()`);
ok((await one(`select holder_id from offices where key='PRES'`)).holder_id === P, 'P is President');
ok((await one(`select holder_id from offices where key='GOV:lagos'`)).holder_id === G, 'G is Governor of Lagos');
ok((await one(`select count(*)::int n from office_terms where citizen_id='${P}' and key='PRES' and end_day is null`)).n === 1, 'term recorded');

// Prices: VAT to the federal treasury, state tax to the state treasury.
await as(P);
await err(`select set_national_policy(0.4, 1)`, /between 0% and 25%/, 'VAT capped at 25%');
await db.query(`select set_national_policy(0.10, 1.5)`);
await err(`select set_national_policy(0.05, 1)`, /again on Day/, 'policy cooldown');
await as(G); await err(`select set_national_policy(0.1, 1)`, /Only the President/, 'governor cannot set national policy');
await db.query(`select set_state_policy(0.05, 0.5)`);
await as(X);
const c0 = await coins(X), f0 = await treas('PRES'), s0 = await treas('GOV:lagos');
await db.query(`select buy_item('house1')`);
ok(c0 - await coins(X) === 3000 + 300 + 150 - 500, 'price = 3,000 + 10% VAT + 5% state tax (minus the 500 Landlord badge)');
ok(await treas('PRES') - f0 === 300, 'VAT goes to the federal treasury');
ok(await treas('GOV:lagos') - s0 === 150, 'state tax goes to the state treasury');
ok(Number((await one(`select _nomination_fee('LG:lagos:lagos-ikeja') f`)).f) === 1000, 'governor halved LG nomination fees');
ok(Number((await one(`select _nomination_fee('SEN:lagos') f`)).f) === 7500, 'president raised national nomination fees by 50%');

// Salaries: only the President sets them; paid from treasuries.
await as(G); await err(`select set_salary('GOV', 5000)`, /Only the President/, 'governor cannot set salaries');
await as(P);
await err(`select set_salary('PRES', 20000)`, /between 0 and 10000/, 'presidential salary capped');
await db.query(`select set_salary('PRES', 8000)`);
await db.query(`select set_salary('GOV', 0)`);
ok((await one(`select count(*)::int n from news where body like '%sets the daily salary of the President%'`)).n === 1, 'salary change in the news');
const pc = await coins(P), gc = await coins(G), ft = await treas('PRES');
await as(null); await db.query(`select advance_day()`);
ok(await coins(P) - pc === 8000, 'President paid the chosen salary');
ok(await coins(G) - gc === 0, 'Governor paid the salary the President set (zero)');
ok(ft - await treas('PRES') >= 8000 - 400, 'salary comes out of the federal treasury');

// Tenure.
await as(P);
await err(`select set_presidential_tenure(200)`, /between 90 and 150/, 'tenure capped at 150 days (5 years)');
await db.query(`select set_presidential_tenure(150)`);
const term = await one(`select o.term_ends_day, e.poll_day from offices o join elections e on e.key = o.key and e.status='open' where o.key='PRES'`);
ok(term.term_ends_day === 2 + 150 && term.poll_day === 152, 'current term and next election moved to 150 days');
ok((await one(`select term_days from office_rules where type='PRES'`)).term_days === 150, 'future terms use the new tenure');

// Office history when voted out.
await as(X); await db.query(`select join_party('${pbc}')`); await db.query(`select stash_coins(500)`);
await db.exec(`update citizens set rep = 50 where id='${X}'; `); await db.query(`select _move('${X}', 'stash', 50000, 'test_grant')`);
const ge = (await one(`select id from elections where key='GOV:lagos' and status='open'`)).id;
await db.query(`select revalidate_card('${ge}')`); await db.query(`select declare_candidacy('GOV:lagos')`);
await db.exec(`update candidates set popularity = 100, real_votes = 50 where citizen_id='${X}'; update candidates set popularity = 0 where citizen_id='${G}' and votes is null`);
await db.exec(`update elections set poll_day = (select day from game_clock) + 1 where id='${ge}'`);
await as(null); await db.query(`select advance_day()`);
const gt = await one(`select ended_how, end_day from office_terms where citizen_id='${G}' and key='GOV:lagos'`);
ok(gt.ended_how === 'voted out' && gt.end_day != null, 'voted-out governor keeps an ex-governor record');

// Ten-term limit.
await db.exec(`insert into office_terms (citizen_id, key, start_day, end_day) select '${G}', 'PRES', g, g from generate_series(1,10) g`);
await as(G);
await db.exec(`update citizens set rep = 50 where id='${G}'; `); await db.query(`select _move('${G}', 'stash', 50000, 'test_grant')`);
const pe = (await one(`select id from elections where key='PRES' and status='open'`)).id;
await db.query(`select revalidate_card('${pe}')`);
await err(`select declare_candidacy('PRES')`, /10 times/, 'presidential limit of 10 wins');

const bad = await db.query(`select w.citizen_id from wallets w where w.coins <> coalesce((select sum(delta) from ledger l where l.citizen_id = w.citizen_id and cur='coins'),0)`);
ok(bad.rows.length === 0, 'ledger still matches wallets');
console.log(`\n${pass} passed, ${fail} failed`); process.exit(fail ? 1 : 0);
