// Tests for 0016: the owner password.
// Run: node tests/owner.test.mjs supabase/migrations
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import fs from 'fs';
const dir = process.argv[2]; const db = new PGlite({ extensions: { pgcrypto } });
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log('FAIL:', m); } };
const one = async (s) => (await db.query(s)).rows[0];
// Each "login" has its own session id in the JWT, like Supabase.
const as = async (u, session = 'sess-1') => {
  await db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [u || '']);
  await db.query(`select set_config('test.session', $1, false)`, [session]);
};
const err = async (s, re, m) => { try { await db.query(s); ok(false, m + ' (no error)'); } catch (e) { ok(re.test(e.message), m + ' -> ' + e.message); } };
await db.exec(`create role anon; create role authenticated; create schema auth; create schema extensions;
  create table auth.users (id uuid primary key, email text, last_sign_in_at timestamptz);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create function auth.jwt() returns jsonb language sql stable as $$ select jsonb_build_object('session_id', current_setting('test.session', true)) $$;`);
for (const f of fs.readdirSync(dir).filter(f => /^\d{4}_.*\.sql$/.test(f) && !/cron|storage|realtime/.test(f)).sort()) {
  try { await db.exec(fs.readFileSync(`${dir}/${f}`, 'utf8')); } catch (e) { console.log('ERROR in', f, e.message); process.exit(1); } }

const O = '11111111-1111-1111-1111-111111111111', X = '22222222-2222-2222-2222-222222222222';
const N = '33333333-3333-3333-3333-333333333333';
await db.exec(`insert into auth.users values ('${O}','owner',now()),('${X}','x',now()),('${N}','new-owner',now())`);
await as(O); await db.query(`select register_citizen('Owner','fct-amac')`);
await as(X); await db.query(`select register_citizen('Player','lagos-ikeja')`);
await db.exec(`insert into admins values ('${O}'), ('${N}')`);
await as(N); await err(`select register_citizen('Owner Two','fct-amac')`, /cannot register as citizens/, 'owner accounts cannot register as citizens');

// Non-owners get nothing.
await as(X);
await err(`select admin_password_status()`, /Owner access only/, 'player cannot see owner status');
await err(`select admin_unlock('anything123')`, /Owner access only/, 'player cannot try passwords');

// Owner without a password cannot use owner tools.
await as(O);
ok((await one(`select admin_password_status() s`)).s.has_password === false, 'no password yet');
await err(`select admin_dashboard()`, /Owner password required/, 'dashboard locked before a password is set');
await err(`select admin_set_password('short1')`, /at least 10/, 'password length enforced');
await err(`select admin_set_password('onlyletterspassword')`, /letters and numbers/, 'password needs letters and numbers');
ok((await one(`select admin_set_password('NigerArea2026!') r`)).r.ok === true, 'owner sets password');
const hash = (await one(`select pass_hash from admin_secrets`)).pass_hash;
ok(hash.startsWith('$2') && !hash.includes('NigerArea2026'), 'stored as a bcrypt hash');
ok((await one(`select admin_dashboard() d`)).d.players.total === 2, 'setting the password unlocks this session');

// A different login session (e.g. a stolen token on another device) is still locked.
await as(O, 'sess-2');
await err(`select admin_dashboard()`, /Owner password required/, 'other sessions stay locked');
const bad = (await one(`select admin_unlock('wrong-pass-1') r`)).r;
ok(bad.ok === false && /4 attempts left/.test(bad.message), 'wrong password counted: ' + bad.message);
ok((await one(`select count(*)::int n from admin_login_log where ok = false`)).n === 1, 'failed attempt is logged (not rolled back)');
for (let i = 0; i < 3; i++) await db.query(`select admin_unlock('wrong-pass-x')`);
const locked = (await one(`select admin_unlock('wrong-pass-5') r`)).r;
ok(/locked until/.test(locked.message), 'fifth wrong attempt locks owner access');
const stillLocked = (await one(`select admin_unlock('NigerArea2026!') r`)).r;
ok(stillLocked.ok === false && /locked/.test(stillLocked.message), 'even the right password is refused while locked');
await db.exec(`update admin_secrets set locked_until = now() - interval '1 second'`);
ok((await one(`select admin_unlock('NigerArea2026!') r`)).r.ok === true, 'right password works after the lock expires');
ok((await one(`select admin_dashboard() d`)).d.players.total === 2, 'unlocked session can use the dashboard');

// Expiry.
await db.exec(`update admin_sessions set expires_at = now() - interval '1 minute' where session_id = 'sess-2'`);
await err(`select admin_dashboard()`, /Owner password required/, 'unlock expires');

// Changing the password needs the current one and signs out other sessions.
await as(O, 'sess-1');
ok((await one(`select admin_set_password('NewPass2027x', 'wrong-old-1') r`)).r.ok === false, 'change refused with the wrong current password');
ok((await one(`select admin_set_password('NewPass2027x', 'NigerArea2026!') r`)).r.ok === true, 'change accepted with the right current password');
ok((await one(`select count(*)::int n from admin_sessions`)).n === 1, 'other sessions signed out after a change');
await db.query(`select admin_lock()`);
await err(`select admin_players('', 10)`, /Owner password required/, 'lock button locks immediately');

// Clients can't read the secret tables even with table grants.
await db.exec(`grant select on all tables in schema public to authenticated; set role authenticated`);
ok((await db.query(`select * from admin_secrets`)).rows.length === 0, 'password hash unreadable by clients');
ok((await db.query(`select * from admin_sessions`)).rows.length === 0, 'sessions unreadable by clients');
await db.exec(`reset role`);

console.log(`\n${pass} passed, ${fail} failed`); process.exit(fail ? 1 : 0);
