# Niger Area backend

Multiplayer server for Niger Area, built on Supabase (Postgres, Auth, Edge Functions, pg_cron).
Real players share one country: the same elections, parties, offices and news feed.

## How it's put together

| Piece | What it does |
|---|---|
| `migrations/0001_schema.sql` | Tables and row-level security. Players can read the game, but only their own wallet and history. |
| `migrations/0002_player_functions.sql` | Every player action (claim coins, gift, join a party, run, campaign, govern) as a server function that checks the rules. |
| `migrations/0003_daily_tick.sql` | `advance_day()`: finishes projects, pays salaries and business income, pays the monthly allocation (FAAC), counts votes, runs EFCC raids. |
| `migrations/0004_seed.sql` | States, LGAs, offices, prices, campaign actions, coin packs, founding parties. |
| `migrations/0005_cron.sql` | Runs the tick at midnight West Africa Time. 1 game day = 1 real day, so an LG term is a month and a presidential term is four months. |
| `functions/ad-reward` | Google AdMob callback. Credits ad coins only after verifying Google's signature. |
| `functions/create-checkout` | Starts a Paystack payment for a coin pack. For the web version only. |
| `functions/paystack-webhook` | Checks Paystack's signature, re-verifies the payment with Paystack, then credits coins once. |

**The main rule:** the app never writes to game tables. It calls functions such as
`supabase.rpc('campaign', { p_action: 'rally' })`. Every coin movement goes through `_move()`,
which updates the balance and adds a row to the ledger, which is never edited or deleted.
The test suite checks that every wallet equals the sum of its ledger rows.

## The three launch risks and how this handles them

**1. Coins worth money.** Coins can be bought but never cashed out. A separate currency,
*civic points*, is earned only by playing: 20 for each daily check-in, 500 for winning office,
and 50 a day for governing with approval of 60% or more. Buying coins never earns points.
Points can be redeemed only for airtime, with a limit of 2,500 points a week (₦500),
and only after a NIN or BVN identity check. Payouts are queued in `redemptions`
for someone to review before any airtime is sent.

**2. Money buying elections.**
- Every race has a spending limit (LG 8,000 · Senate 20,000 · Governor 40,000 · President 120,000),
  enforced in `campaign()`.
- Running needs *reputation* (Senate 8, Governor 15, President 30). Reputation is earned
  only through play: showing up daily, governing, debates and town halls.
- *Status* from houses, cars and gifts is capped at 20. After that, money adds nothing.
- Each party gets one ticket per race.

**3. Farming and fraud.**
- Free coins are capped server-side: 1,000 a day plus 5 ads × 200, verified by Google.
- Civic points, gifting, running for office and founding a party all need a phone number verified by SMS code (`kyc_level ≥ 1`).
- Gifts are limited to 2,000 sent and 5,000 received a day. Both accounts must be 7+ days old.
- Paystack webhooks and ad callbacks can be replayed safely: each payment reference and ad transaction is credited once.
- `credit_*` functions and `advance_day()` can't be called by players.

## Run the tests

```bash
npm install
```

```bash
npm test
```

This loads every migration except the cron job into PGlite, an in-process Postgres, and plays
through signup, gifting limits, party tickets, the spending limit, the security rules, 150 days
of ticks, the ledger balance check, payment replays and the ad cap. Current result: 23 passed, 0 failed.

## Deploy

1. Create a Supabase project and link it with `supabase link`.
2. Turn on **Phone** sign-in (SMS OTP) under Auth. Add a hook or admin tool that sets
   `citizens.kyc_level = 1` once the phone is confirmed, and `2` after a NIN/BVN check
   through a provider such as Smile ID, Dojah or Prembly.
3. Push the database:
   ```bash
   supabase db push
   ```
4. Set the edge function secrets:
   ```bash
   supabase secrets set PAYSTACK_SECRET_KEY=sk_test_xxx APP_ORIGIN=https://your-domain
   ```
5. Deploy the functions:
   ```bash
   supabase functions deploy create-checkout
   ```
   ```bash
   supabase functions deploy paystack-webhook --no-verify-jwt
   ```
   ```bash
   supabase functions deploy ad-reward --no-verify-jwt
   ```
6. In the Paystack dashboard, set the webhook URL to `https://<project>.supabase.co/functions/v1/paystack-webhook`.
7. In AdMob, set the rewarded ad unit's server-side verification URL to `.../functions/v1/ad-reward`.

Use Paystack **test** keys until a lawyer has signed off on the economy.

## Not ported from the prototype yet

- INEC chairman role and bribe offers
- Election tribunal petitions
- Presidential diplomacy (state visits, loans, ECOWAS summit)
- Random national events (fuel scarcity, grid collapse, floods, ASUU strikes)
- Senate bills

These are game rules, not infrastructure. Each is one more function in `0002` or a few lines in `advance_day()`.

## Decisions still open

- **Legal review.** Have a Nigerian lawyer check the coin and reward design, and whether airtime rewards need a licence.
- **App store payments.** In the Android and iOS apps, coins must be sold through Google Play Billing and Apple In-App Purchase, not Paystack. That needs a receipt-verification function like `paystack-webhook`.
- **Airtime provider.** Pick one (for example VTpass or Reloadly) and write the payout job that processes approved `redemptions`.
- **Player client.** The prototype page stores everything locally. The multiplayer client will read the tables above and call the functions.
