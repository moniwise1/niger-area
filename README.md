# Niger Area

A multiplayer browser game of Nigerian politics. Citizens collect a PVC, hustle, join or found parties, vote, and run for LG Chairman, Senator, Governor or President across all 36 states and the FCT.

**Live:** https://niger-area-web.vercel.app · **Owner dashboard:** https://niger-area-web.vercel.app/admin

## What's in this repo

| Folder | What it is |
|---|---|
| `niger-area-web/` | The game and the owner dashboard. Plain HTML, CSS and JavaScript, deployed to Vercel. |
| `niger-area-backend/` | Supabase backend: database migrations (game rules live in SQL functions), edge functions for payments and ads, and PGlite test suites. See its README. |
| `prototype/` | The first single-player prototype. |

## How it fits together

- Every player action is a Postgres function called through `supabase.rpc(...)`. The browser can read game data but cannot change coins, votes or offices directly; row-level security blocks direct writes.
- Every coin movement goes through `_move()` and is recorded in an append-only ledger.
- The day advances once at midnight West Africa Time (pg_cron). There is no way to skip days.
- The owner dashboard needs an owner account plus a separate bcrypt-hashed owner password, enforced in the database.

## Running locally

```bash
node niger-area-web/serve.mjs
```

Then open http://localhost:5173. The page talks to the live Supabase project.

## Tests

```bash
cd niger-area-backend && npm install
```

```bash
node tests/power.test.mjs supabase/migrations
```

Suites: `engagement`, `rule_of_law`, `social`, `marriage`, `power`, `owner` (plus `db` for the original schema).

## Deploying

- **Database:** apply new files in `niger-area-backend/supabase/migrations` in order.
- **Site:** from `niger-area-web`, run `npx vercel deploy --prod`.

## Secrets

No secret keys are stored in this repo. The Supabase key in `common.js` is the *publishable* key, which is safe in the browser. The Paystack secret key lives only in Supabase Edge Function secrets.
