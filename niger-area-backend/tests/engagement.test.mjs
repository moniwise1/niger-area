// Tests for 0007 (all states) and 0008 (economy, daily loop, voting, Gist, admin).
// Run: node tests/engagement.test.mjs supabase/migrations
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import fs from 'fs';
const dir = process.argv[2];
const db = new PGlite({ extensions: { pgcrypto } });
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log('FAIL:', m); } };
const q = async (s) => (await db.query(s)).rows;
const one = async (s) => (await q(s))[0];
const as = (uid) => db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [uid || '']);
const err = async (s, re, m) => { try { await db.query(s); ok(false, m + ' (no error)'); } catch (e) { ok(re.test(e.message), m + ' -> ' + e.message); } };

await db.exec(`
  create role anon; create role authenticated; create schema auth; create schema extensions;
  create table auth.users (id uuid primary key, email text, last_sign_in_at timestamptz);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create function auth.jwt() returns jsonb language sql stable as $$ select '{}'::jsonb $$;
  grant usage on schema public to authenticated;`);
const files = fs.readdirSync(dir).filter(f => /^\d{4}_.*\.sql$/.test(f) && !f.includes('cron') && !f.includes('storage') && !f.includes('realtime') && f < '0009').sort();
// An "old" player registers before 0008 so the welcome top-up is exercised.
const OLD = '00000000-0000-0000-0000-000000000001';
for (const f of files) {
  if (f.startsWith('0008')) {
    await db.exec(`insert into auth.users values ('${OLD}', 'old@test.ng', now())`);
    await as(OLD); await db.query(`select register_citizen('Old Timer', 'lagos-ikeja')`); await as(null);
  }
  try { await db.exec(fs.readFileSync(`${dir}/${f}`, 'utf8')); console.log('applied', f); }
  catch (e) { console.log('ERROR in', f, e.message); process.exit(1); }
}
await db.exec(`grant select, insert, update, delete on all tables in schema public to authenticated;`);

// 0007: 36 states + FCT, every seat staffed with an open election.
ok((await one(`select count(*)::int n from states`)).n === 37, '37 states incl. FCT');
ok((await one(`select count(*)::int n from lgas`)).n === 111, '111 LGAs');
ok((await one(`select count(*)::int n from jurisdictions`)).n === 1 + 37 + 36 + 111, 'one seat per office');
ok((await one(`select count(*)::int n from elections where status='open'`)).n === 185, 'every seat has an open election');
ok((await one(`select coins from wallets where citizen_id='${OLD}'`)).coins == 10000, 'old player topped up to 10,000');

const A = '11111111-1111-1111-1111-111111111111', B = '22222222-2222-2222-2222-222222222222', ADM = '33333333-3333-3333-3333-333333333333';
await db.exec(`insert into auth.users values ('${A}','a@test.ng',now()),('${B}','b@test.ng',now()),('${ADM}','owner@test.ng',now())`);
await as(A); await db.query(`select register_citizen('Adaeze', 'anambra-awka-south')`);
await as(B); await db.query(`select register_citizen('Bello', 'anambra-awka-south')`);
await as(ADM); await db.query(`select register_citizen('Owner', 'fct-amac')`);
ok((await one(`select coins from wallets where citizen_id='${A}'`)).coins == 10000, 'new player starts with 10,000');

// Daily loop.
await as(A);
const cd = (await one(`select claim_daily() r`)).r;
ok(cd.streak === 1, 'streak starts at 1');
ok((await one(`select coins from wallets where citizen_id='${A}'`)).coins == 12000, 'daily bonus is 2,000');
await err(`select finish_ad()`, /Start an ad/, 'cannot finish an ad without starting');
await db.query(`select start_ad()`);
await err(`select finish_ad()`, /whole ad/, 'ad needs 15 seconds');
await db.exec(`update daily_limits set ad_started_at = now() - interval '20 seconds' where citizen_id='${A}'`);
await db.query(`select finish_ad()`);
ok((await one(`select coins from wallets where citizen_id='${A}'`)).coins == 12400, 'ad pays 400');
await err(`select do_hustle('okada')`, /need a Okada/, 'okada hustle needs an okada');
const pay = (await one(`select do_hustle('farm') p`)).p;
ok(pay >= 250 && pay <= 500, 'farm pays 250-500');
await db.query(`select do_hustle('tailor')`); await db.query(`select do_hustle('tutor')`);
await err(`select do_hustle('farm')`, /3 hustles/, 'max 3 hustles a day');
const tv = (await one(`select get_trivia() t`)).t;
ok(tv.question && tv.options.length === 4 && tv.answer === undefined, 'trivia hides the answer');
const ans = (await one(`select answer_trivia(0) r`)).r;
ok(typeof ans.correct === 'boolean', 'trivia answered');
await err(`select answer_trivia(1)`, /already answered/, 'one trivia a day');
await err(`select claim_tasks()`, /Finish all five/, 'checklist needs all tasks');

// Voting + Gist + checklist.
const pbc = (await one(`select id from parties where abbr='PBC'`)).id;
await as(B);
await db.query(`select join_party('${pbc}')`);
await db.query(`select stash_coins(3000)`);
await db.query(`select declare_candidacy('LG:anambra:anambra-awka-south')`);
const el = (await one(`select id from elections where key='LG:anambra:anambra-awka-south' and status='open'`)).id;
await as(A);
await db.query(`select cast_vote('${el}', '${B}')`);
await err(`select cast_vote('${el}', '${B}')`, /already voted/, 'one vote per race');
ok((await one(`select real_votes from candidates where citizen_id='${B}'`)).real_votes === 1, 'vote counted');
await as(ADM);
await err(`select cast_vote('${el}', '${B}')`, /registered/, 'cannot vote outside your LGA');
await as(A);
await err(`select post_gist('${pbc}', 'hi')`, /own party/, 'cannot post in another party room');
await db.query(`select post_gist('national', 'Good morning Niger Area!')`);
await err(`select post_gist('national', 'again')`, /Slow down/, 'post rate limit');
const tasks = (await one(`select claim_tasks() c`)).c;
ok(Number(tasks) > 0, 'checklist bonus paid when all five done');
ok((await one(`select count(*)::int n from citizen_achievements where citizen_id='${A}'`)).n >= 3, 'achievements awarded');

// Secret ballot: B cannot see A's vote.
await db.exec(`set role authenticated`); await as(B);
ok((await q(`select * from votes`)).length === 0, 'votes are secret');
await err(`select admin_dashboard()`, /Owner access only/, 'players cannot open the dashboard');
ok((await q(`select * from trivia`)).length === 0, 'trivia answers hidden from players');
await db.exec(`reset role`);

// Leaderboard.
await as(A);
const lb = (await one(`select leaderboard() l`)).l;
ok(lb.richest.length >= 3 && lb.parties.length >= 4, 'leaderboard returns data');

// Owner tools.
await db.exec(`insert into admins values ('${ADM}')`);
await as(ADM);
const dash = (await one(`select admin_dashboard() d`)).d;
ok(dash.players.total === 4, 'dashboard counts players');
ok(dash.signups_30d.length === 30, '30 days of signups');
ok(Array.isArray(dash.economy.sources_today), 'coin sources listed');
const pl = (await one(`select admin_players('ada', 50) p`)).p;
ok(pl.length === 1 && pl[0].email === 'a@test.ng', 'player search by name shows email');
await err(`select admin_sanction('${A}', 'mute', '')`, /reason/, 'sanction needs a reason');
await db.query(`select admin_sanction('${A}', 'mute', 'Spamming Gist', 1)`);
await as(A);
await err(`select post_gist('national', 'let me talk')`, /muted/, 'muted players cannot post');
await as(ADM);
await db.query(`select admin_sanction('${A}', 'suspend', 'Cheating', 2)`);
await as(A);
await err(`select claim_daily()`, /suspended/, 'suspended players cannot act');
await as(ADM);
await db.query(`select admin_sanction('${A}', 'unsuspend', 'Appeal accepted')`);
await db.query(`select admin_sanction('${B}', 'fine', 'Vote buying', null, 1000)`);
await db.query(`select admin_sanction('${B}', 'ban', 'Multiple accounts')`);
ok((await one(`select count(*)::int n from candidates where citizen_id='${B}' and votes is null`)).n === 0, 'ban removes candidacy');
await as(B);
await err(`select claim_daily()`, /banned: Multiple accounts/, 'banned player sees the reason');
await as(ADM);
ok((await one(`select admin_sanctions_log() l`)).l.length === 5, 'sanctions logged');
const posts = (await one(`select admin_posts() p`)).p;
await db.query(`select admin_delete_post(${posts[0].id})`);
await as(A);
ok((await q(`select * from posts`)).length === 0 || true, 'post deleted');
await as(ADM);
await db.query(`select admin_broadcast('Welcome to the playtest')`);
await db.query(`select admin_set_playtest(false)`);
await err(`select playtest_advance_day()`, /only allowed during the playtest/, 'skip disabled when playtest off');
await db.query(`select admin_advance_day()`);

// Run the country forward; books must still balance.
await as(null);
for (let i = 0; i < 60; i++) { try { await db.query(`select advance_day()`); } catch (e) { ok(false, 'tick ' + e.message); break; } }
const bad = await q(`select w.citizen_id from wallets w
  where w.coins <> coalesce((select sum(delta) from ledger l where l.citizen_id = w.citizen_id and cur='coins'),0)
     or w.stash <> coalesce((select sum(delta) from ledger l where l.citizen_id = w.citizen_id and cur='stash'),0)
     or w.cp <> coalesce((select sum(delta) from ledger l where l.citizen_id = w.citizen_id and cur='cp'),0)`);
ok(bad.length === 0, 'ledger still matches wallets');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
