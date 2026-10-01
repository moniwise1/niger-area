// Tests for 0014: marriage between players, campaign posts, likes.
// Run: node tests/marriage.test.mjs supabase/migrations
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import fs from 'fs';
const dir = process.argv[2]; const db = new PGlite({ extensions: { pgcrypto } });
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log('FAIL:', m); } };
const one = async (s) => (await db.query(s)).rows[0];
const as = (u) => db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [u || '']);
const err = async (s, re, m) => { try { await db.query(s); ok(false, m + ' (no error)'); } catch (e) { ok(re.test(e.message), m + ' -> ' + e.message); } };
await db.exec(`create role anon; create role authenticated; create schema auth; create schema extensions;
  create table auth.users (id uuid primary key, email text, last_sign_in_at timestamptz);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create function auth.jwt() returns jsonb language sql stable as $$ select '{}'::jsonb $$;
  grant usage on schema public to authenticated;`);
for (const f of fs.readdirSync(dir).filter(f => /^\d{4}_.*\.sql$/.test(f) && !/cron|storage|realtime/.test(f)).sort()) {
  try { await db.exec(fs.readFileSync(`${dir}/${f}`, 'utf8')); } catch (e) { console.log('ERROR in', f, e.message); process.exit(1); } }
await db.exec(`grant select, insert, update, delete on all tables in schema public to authenticated;`);
const A='11111111-1111-1111-1111-111111111111', B='22222222-2222-2222-2222-222222222222', C='33333333-3333-3333-3333-333333333333';
await db.exec(`insert into auth.users values ('${A}','a',now()),('${B}','b',now()),('${C}','c',now())`);
for (const [u,n] of [[A,'Tunde'],[B,'Funke'],[C,'Emeka']]) { await as(u); await db.query(`select register_citizen('${n}','lagos-ikeja')`); }
const coins = async u => Number((await one(`select coins from wallets where citizen_id='${u}'`)).coins);
await as(A); await err(`select buy_item('spouse')`, /propose/, 'marriage not in the shop');
await err(`select buy_item('child')`, /married first/, 'children need marriage');
const c0 = await coins(A);
await db.query(`select propose('${B}', 'Will you marry me?')`);
ok(c0 - await coins(A) === 6000, 'proposer pays 6,000');
await err(`select propose('${C}')`, /already have a proposal/, 'one proposal at a time');
await as(B); await db.query(`select answer_proposal('${A}', false)`);
ok(await coins(A) === c0, 'declined proposal refunded');
await as(A); await db.query(`select propose('${B}')`);
await as(B); await db.query(`select answer_proposal('${A}', true)`);
ok((await one(`select public_spouse('${A}') s`)).s.name === 'Funke', 'spouse shown on profile');
ok((await one(`select count(*)::int n from news where body like '%wed in a colourful ceremony%'`)).n === 1, 'wedding in the news');
await as(C); await err(`select propose('${A}')`, /already married/, 'cannot propose to a married person');
await as(A); await db.query(`select set_show_spouse(false)`);
ok((await one(`select public_spouse('${A}') s`)).s === null, 'spouse hidden when chosen');
await db.query(`select buy_item('child')`); ok(true, 'married couple can have children');
// spouse is not readable from citizens by other players
await db.exec(`set role authenticated`); await as(C);
ok((await db.query(`select * from marriages`)).rows.length === 0, 'marriages private to the couple');
await db.exec(`reset role`);
await as(B); await db.query(`select divorce()`);
ok((await one(`select public_spouse('${B}') s`)).s === null, 'divorce clears spouse');
// Campaign posts and likes
const pbc=(await one(`select id from parties where abbr='PBC'`)).id;
const el=(await one(`select id from elections where key='LG:lagos:lagos-ikeja' and status='open'`)).id;
await as(C); await err(`select post_campaign('Vote me')`, /Only candidates/, 'only candidates can post campaign messages');
await db.query(`select join_party('${pbc}')`); await db.query(`select stash_coins(3000)`);
await db.query(`select revalidate_card('${el}')`); await db.query(`select declare_candidacy('LG:lagos:lagos-ikeja')`);
const pid = (await one(`select post_campaign('Vote Emeka for Ikeja! Light, roads, jobs.') p`)).p;
ok((await one(`select election_id from posts where id=${pid}`)).election_id === el, 'campaign post linked to the race');
await err(`select post_campaign('again')`, /every 30 minutes/, 'campaign post rate limit');
await as(A); ok((await one(`select toggle_like(${pid}) n`)).n === 1, 'like');
ok((await one(`select toggle_like(${pid}) n`)).n === 0, 'unlike');
console.log(`\n${pass} passed, ${fail} failed`); process.exit(fail ? 1 : 0);
