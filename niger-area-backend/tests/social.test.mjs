// Tests for 0010 (news) and 0011 (profiles, connections, chat, reports).
// Run: node tests/social.test.mjs supabase/migrations
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
for (const f of fs.readdirSync(dir).filter(f => /^\d{4}_.*\.sql$/.test(f) && !f.includes('cron') && !f.includes('storage') && !f.includes('realtime')).sort()) {
  try { await db.exec(fs.readFileSync(`${dir}/${f}`, 'utf8')); } catch (e) { console.log('ERROR in', f, e.message); process.exit(1); }
}
await db.exec(`grant select, insert, update, delete on all tables in schema public to authenticated;`);

const A = '11111111-1111-1111-1111-111111111111', B = '22222222-2222-2222-2222-222222222222',
      C = '33333333-3333-3333-3333-333333333333', O = '44444444-4444-4444-4444-444444444444';
await db.exec(`insert into auth.users values ('${A}','a@t',now()),('${B}','b@t',now()),('${C}','c@t',now()),('${O}','o@t',now())`);
for (const [u, n] of [[A, 'Amaka'], [B, 'Bayo'], [C, 'Chidi'], [O, 'Owner']]) { await as(u); await db.query(`select register_citizen('${n}', 'lagos-ikeja')`); }
await db.exec(`insert into admins values ('${O}'); insert into admin_sessions (user_id, session_id, expires_at) values ('${O}', '', now() + interval '1 hour')`);

// Profile.
await as(B);
await db.query(`select update_profile('Ikeja boy. Running for chairman.', 'connections')`);
await err(`select update_profile('x', 'strangers')`, /who can message/, 'dm policy validated');
await err(`select set_avatar('https://evil.example/x.png')`, /through the game/, 'avatar must come from own storage folder');
await db.query(`select set_avatar('https://p.supabase.co/storage/v1/object/public/avatars/${B}/me.webp')`);
ok((await one(`select avatar_url from citizens where id='${B}'`)).avatar_url.endsWith('me.webp'), 'avatar saved');

// Chat policy: B only accepts connections.
await as(A);
await err(`select send_message('${B}', 'Hello')`, /only accepts messages from connections/, 'connections-only blocks strangers');
ok((await one(`select request_connection('${B}') r`)).r === 'requested', 'request sent');
await err(`select request_connection('${B}')`, /still waiting/, 'no duplicate request');
await as(B);
await db.query(`select respond_connection('${A}', true)`);
await as(A);
await db.query(`select send_message('${B}', 'Hello Bayo, we go win this election')`);
await as(B);
await db.query(`select send_message('${A}', 'Amaka! Welcome')`);
const conv = (await one(`select my_conversations() c`)).c;
ok(conv.length === 1 && conv[0].unread === 1, 'conversation listed with unread count');
await db.query(`select mark_read('${A}')`);
ok((await one(`select my_conversations() c`)).c[0].unread === 0, 'mark read clears unread');

// Nobody policy, but replies are allowed once they wrote first.
await as(C); await db.query(`select update_profile(null, 'nobody')`);
await as(A); await err(`select send_message('${C}', 'hi')`, /not accepting messages/, 'nobody policy blocks');
await as(C); await db.exec(`update citizens set dm_policy='everyone' where id='${C}'`);
await db.query(`select send_message('${A}', 'I wrote first')`);
await db.exec(`update citizens set dm_policy='nobody' where id='${C}'`);
await as(A); await db.query(`select send_message('${C}', 'replying is fine')`);
ok(true, 'reply allowed after they messaged you');

// Privacy: a third party can't read others' messages or connections.
await db.exec(`set role authenticated`); await as(O);
ok((await q(`select * from messages`)).length === 0, 'messages private to the two people');
ok((await q(`select * from connections`)).length === 0, 'connections private');
await db.exec(`reset role`);

// Reports.
await as(A); await db.query(`select report_citizen('${C}', 'Insulting me in DMs')`);
await as(O);
const reps = (await one(`select admin_reports() r`)).r;
ok(reps.length === 1 && reps[0].target === 'Chidi', 'owner sees the report');
ok((await one(`select admin_report_messages(${reps[0].id}) m`)).m.length === 2, 'owner can read only the reported conversation');
await db.query(`select admin_close_report(${reps[0].id})`);

// News for sanctions and categories.
await db.query(`select admin_sanction('${C}', 'mute', 'Abusive messages', 2)`);
ok((await one(`select kind from news where body like 'Chidi is muted%'`)).kind === 'law', 'mute makes law news');
await as(C); await err(`select send_message('${A}', 'let me talk')`, /muted/, 'muted players cannot DM');
ok((await one(`select kind from news where body like '%joins the%' or body like '%collects a PVC%' order by id desc limit 1`)) !== undefined, 'news written');

// Detained players can't chat.
await db.exec(`update citizens set detained_until = now() + interval '1 hour', muted_until = null where id='${A}'`);
await as(A); await err(`select send_message('${B}', 'help')`, /custody/, 'detained players cannot chat');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
