-- Niger Area: core schema.
-- Rule of the house: clients never write game tables directly. Every change to coins,
-- votes or offices goes through a SECURITY DEFINER function in 0002/0003, which checks
-- limits and writes an append-only ledger row.

create type office_type as enum ('LG', 'SEN', 'GOV', 'PRES');
create type currency as enum ('coins', 'stash', 'cp');

-- One row. 1 game day = 1 real day, advanced by pg_cron at midnight WAT (0003).
create table game_clock (
  id          int primary key default 1 check (id = 1),
  day         int not null default 1,
  alloc_boost numeric not null default 1
);
insert into game_clock default values;

create table states (
  id           text primary key,
  name         text not null,
  has_governor boolean not null default true   -- false for Abuja FCT (appointed minister)
);

create table lgas (
  id       text primary key,
  state_id text not null references states,
  name     text not null
);

create table office_rules (
  type         office_type primary key,
  title        text   not null,
  term_days    int    not null,
  fee          bigint not null,   -- nomination fee, paid from stash
  salary       bigint not null,   -- coins per day to the holder
  alloc        bigint not null,   -- monthly FAAC allocation to the treasury
  project_cost bigint not null,
  min_rep      int    not null,   -- earned reputation needed to run
  spend_cap    bigint not null,   -- campaign spending limit per race
  cost_mult    int    not null,   -- multiplier on campaign action prices
  voters_min   int    not null,
  voters_max   int    not null
);

-- ---------- Citizens and money ----------

create table citizens (
  id                uuid primary key references auth.users on delete cascade,
  display_name      text not null check (char_length(display_name) between 2 and 40),
  state_id          text not null references states,
  lga_id            text not null references lgas,
  created_at        timestamptz not null default now(),
  -- 0 = email only, 1 = phone OTP verified, 2 = NIN/BVN verified (needed to redeem rewards)
  kyc_level         int not null default 0,
  banned            boolean not null default false,
  energy            int not null default 6,
  energy_day        int not null default 0,
  integrity         numeric not null default 50,
  scandal           numeric not null default 0,
  rep               numeric not null default 0 check (rep >= 0),   -- earned only by playing
  gift_status       numeric not null default 0,                   -- status bought via gifts
  offices_held      int not null default 0
);

create table wallets (
  citizen_id       uuid primary key references citizens on delete cascade,
  coins            bigint not null default 1500 check (coins >= 0),
  stash            bigint not null default 0    check (stash >= 0),
  cp               bigint not null default 0    check (cp >= 0),     -- civic points, never purchasable
  purchased_total  bigint not null default 0                         -- lifetime coins bought, for audits
);

-- Append-only. Balances in `wallets` must always equal the sum of this table per currency.
create table ledger (
  id              bigserial primary key,
  citizen_id      uuid not null references citizens,
  cur             currency not null,
  delta           bigint not null,
  balance_after   bigint not null,
  reason          text not null,
  ref             text,
  idempotency_key text unique,
  created_at      timestamptz not null default now()
);
create index ledger_citizen_idx on ledger (citizen_id, created_at desc);

create table daily_limits (
  citizen_id uuid not null references citizens on delete cascade,
  day        int  not null,
  claimed    boolean not null default false,
  ads        int    not null default 0,
  gifted     bigint not null default 0,
  primary key (citizen_id, day)
);

-- ---------- Household ----------

create table shop_items (
  id            text primary key,
  label         text   not null,
  kind          text   not null check (kind in ('house', 'car', 'extra', 'family', 'business')),
  tier          int    not null default 0,   -- houses and cars must be bought in order
  cost          bigint not null,
  status_points int    not null,
  daily_income  bigint not null default 0,
  max_qty       int    not null default 1,
  requires      text references shop_items
);

create table citizen_items (
  citizen_id uuid not null references citizens on delete cascade,
  item_id    text not null references shop_items,
  qty        int  not null default 1 check (qty > 0),
  primary key (citizen_id, item_id)
);

-- ---------- Parties ----------

create table parties (
  id           uuid primary key default gen_random_uuid(),
  name         text not null unique check (char_length(name) between 3 and 40),
  abbr         text not null unique check (abbr ~ '^[A-Z]{2,6}$'),
  color        text not null check (color ~ '^#[0-9A-Fa-f]{6}$'),
  chair_id     uuid references citizens,
  base_members bigint not null default 0,   -- seeded founding parties; player parties start at 0
  created_at   timestamptz not null default now()
);

create table party_members (
  citizen_id uuid primary key references citizens on delete cascade,
  party_id   uuid not null references parties on delete cascade,
  role       text not null default 'member' check (role in ('member', 'chair')),
  joined_day int  not null
);
create index party_members_party_idx on party_members (party_id);

-- ---------- Government ----------

create table jurisdictions (
  key      text primary key,              -- 'PRES', 'GOV:lagos', 'SEN:lagos', 'LG:lagos:ikeja'
  type     office_type not null,
  state_id text references states,
  lga_id   text references lgas,
  roads    numeric not null default 40, power numeric not null default 40,
  health   numeric not null default 40, edu   numeric not null default 40,
  security numeric not null default 40, economy numeric not null default 40,
  mood     numeric not null default 0,
  treasury bigint  not null default 0,
  debt     bigint  not null default 0,
  last_salary_day int not null default 0
);

create table offices (
  key            text primary key references jurisdictions,
  holder_id      uuid references citizens,    -- null = caretaker committee
  holder_party   uuid references parties,
  term_ends_day  int not null
);
create unique index one_office_per_citizen on offices (holder_id) where holder_id is not null;

create table elections (
  id       uuid primary key default gen_random_uuid(),
  key      text not null references jurisdictions,
  poll_day int  not null,
  status   text not null default 'open' check (status in ('open', 'closed')),
  turnout  bigint
);
create unique index one_open_election_per_office on elections (key) where status = 'open';

create table candidates (
  election_id uuid not null references elections on delete cascade,
  citizen_id  uuid not null references citizens,
  party_id    uuid not null references parties,
  popularity  numeric not null default 0,
  spent       bigint  not null default 0,
  votes       bigint,
  primary key (election_id, citizen_id),
  unique (election_id, party_id)             -- one ticket per party: the primary is first-come
);
create unique index one_race_per_citizen on candidates (citizen_id) where votes is null;

create table campaign_actions (
  id        text primary key,
  label     text not null,
  base_cost bigint not null,
  energy    int not null,
  pop_min   numeric not null,
  pop_max   numeric not null,
  scandal   numeric not null default 0,
  integrity numeric not null default 0,
  need_rep  int not null default 0,
  rep_gain  numeric not null default 0
);

create table projects (
  id         bigserial primary key,
  key        text not null references jurisdictions,
  stat       text not null check (stat in ('roads','power','health','edu','security','economy')),
  gain       numeric not null,
  ready_day  int not null,
  started_by uuid references citizens,
  done       boolean not null default false
);

create table news (
  id         bigserial primary key,
  day        int  not null,
  body       text not null,
  created_at timestamptz not null default now()
);

-- ---------- Money in and rewards out ----------

-- Filled by the ad-reward edge function after verifying Google's SSV signature.
create table ad_rewards (
  transaction_id text primary key,
  citizen_id     uuid not null references citizens,
  coins          bigint not null,
  created_at     timestamptz not null default now()
);

-- Created by create-checkout, completed by the verified Paystack webhook.
create table purchases (
  reference  text primary key,
  citizen_id uuid not null references citizens,
  pack_id    text not null,
  kobo       bigint not null,
  coins      bigint not null,
  status     text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  created_at timestamptz not null default now(),
  paid_at    timestamptz
);

create table coin_packs (
  id    text primary key,
  kobo  bigint not null,   -- price in kobo (₦1 = 100 kobo)
  coins bigint not null
);

-- Airtime redemptions are reviewed before payout. Only civic points can be redeemed.
create table redemptions (
  id         bigserial primary key,
  citizen_id uuid not null references citizens,
  cp         bigint not null,
  naira      bigint not null,
  phone      text not null check (phone ~ '^\+234[0-9]{10}$'),
  status     text not null default 'pending' check (status in ('pending', 'paid', 'rejected')),
  created_at timestamptz not null default now()
);

-- ---------- Row level security ----------
-- Everything is readable by signed-in players except private money tables.
-- No table has an insert/update/delete policy: writes only happen inside definer functions.

alter table game_clock       enable row level security;
alter table states           enable row level security;
alter table lgas             enable row level security;
alter table office_rules     enable row level security;
alter table citizens         enable row level security;
alter table wallets          enable row level security;
alter table ledger           enable row level security;
alter table daily_limits     enable row level security;
alter table shop_items       enable row level security;
alter table citizen_items    enable row level security;
alter table parties          enable row level security;
alter table party_members    enable row level security;
alter table jurisdictions    enable row level security;
alter table offices          enable row level security;
alter table elections        enable row level security;
alter table candidates       enable row level security;
alter table campaign_actions enable row level security;
alter table projects         enable row level security;
alter table news             enable row level security;
alter table ad_rewards       enable row level security;
alter table purchases        enable row level security;
alter table coin_packs       enable row level security;
alter table redemptions      enable row level security;

create policy read_all on game_clock       for select to authenticated using (true);
create policy read_all on states           for select to authenticated using (true);
create policy read_all on lgas             for select to authenticated using (true);
create policy read_all on office_rules     for select to authenticated using (true);
create policy read_all on citizens         for select to authenticated using (true);
create policy read_all on shop_items       for select to authenticated using (true);
create policy read_all on citizen_items    for select to authenticated using (true);
create policy read_all on parties          for select to authenticated using (true);
create policy read_all on party_members    for select to authenticated using (true);
create policy read_all on jurisdictions    for select to authenticated using (true);
create policy read_all on offices          for select to authenticated using (true);
create policy read_all on elections        for select to authenticated using (true);
create policy read_all on candidates       for select to authenticated using (true);
create policy read_all on campaign_actions for select to authenticated using (true);
create policy read_all on projects         for select to authenticated using (true);
create policy read_all on news             for select to authenticated using (true);
create policy read_all on coin_packs       for select to authenticated using (true);

create policy read_own on wallets      for select to authenticated using (citizen_id = auth.uid());
create policy read_own on ledger       for select to authenticated using (citizen_id = auth.uid());
create policy read_own on daily_limits for select to authenticated using (citizen_id = auth.uid());
create policy read_own on purchases    for select to authenticated using (citizen_id = auth.uid());
create policy read_own on redemptions  for select to authenticated using (citizen_id = auth.uid());
-- ad_rewards: no client access at all.
