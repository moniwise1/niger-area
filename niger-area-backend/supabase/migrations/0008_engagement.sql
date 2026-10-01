-- Niger Area: richer economy and daily play.
--   10,000 welcome coins, 2,000 daily sign-in, up to 2,000 more from ads (5 x 400)
--   streaks, side hustles, daily trivia, daily checklist, real player voting,
--   achievements, Gist (national + party chat), leaderboards, profiles.

-- ---------- Columns ----------
alter table citizens add column streak int not null default 0;
alter table citizens add column best_streak int not null default 0;
alter table citizens add column last_checkin_day int not null default 0;
alter table citizens add column hustles_total int not null default 0;
alter table citizens add column trivia_correct int not null default 0;
alter table citizens add column votes_cast int not null default 0;
alter table citizens add column posts_total int not null default 0;
alter table citizens add column suspended_until timestamptz;
alter table citizens add column muted_until timestamptz;
alter table citizens add column ban_reason text;
alter table citizens add column last_seen timestamptz;
alter table citizens alter column energy set default 8;

alter table daily_limits add column hustles int not null default 0;
alter table daily_limits add column trivia_done boolean not null default false;
alter table daily_limits add column civic boolean not null default false;     -- voted or campaigned
alter table daily_limits add column posted boolean not null default false;
alter table daily_limits add column tasks_claimed boolean not null default false;
alter table daily_limits add column ad_started_at timestamptz;

alter table candidates add column real_votes int not null default 0;

-- ---------- New tables ----------
create table hustles (
  id text primary key, label text not null, blurb text not null,
  energy int not null, min_pay int not null, max_pay int not null,
  needs_item text references shop_items, rep_gain numeric not null default 0
);
insert into hustles values
  ('farm',   'Work on the farm',          'Harvest yams before the rains.',             1, 250,  500, null,   0),
  ('tailor', 'Sew aso-ebi orders',        'Wedding season never ends.',                 1, 300,  650, null,   0),
  ('tutor',  'Teach JAMB lessons',        'Help the next generation pass. +reputation.',1, 350,  600, null,   0.2),
  ('pos',    'Run a POS shift',           'Cash-out for the whole street.',             1, 400,  800, 'pos',  0),
  ('okada',  'Ride okada',                'Beat Lagos traffic. Needs an okada.',        1, 450,  900, 'car1', 0),
  ('market', 'Trade at Balogun market',   'Two energy, big margins.',                   2, 700, 1400, null,   0);

-- Answer column is never exposed to clients; questions come through get_trivia().
create table trivia (id int primary key, question text not null, options text[] not null, answer int not null);
insert into trivia values
  (1,  'How many states does Nigeria have?', '{"30","36","37","40"}', 1),
  (2,  'What is the capital of Nigeria?', '{"Lagos","Kaduna","Abuja","Ibadan"}', 2),
  (3,  'In what year did Nigeria gain independence?', '{"1957","1960","1963","1966"}', 1),
  (4,  'In what year did Nigeria become a republic?', '{"1960","1963","1979","1999"}', 1),
  (5,  'In what year did the seat of government move from Lagos to Abuja?', '{"1976","1985","1991","1999"}', 2),
  (6,  'How many local government areas does Nigeria have?', '{"536","650","774","812"}', 2),
  (7,  'How many senators sit in the Nigerian Senate?', '{"96","109","120","360"}', 1),
  (8,  'How many members sit in the House of Representatives?', '{"109","250","360","400"}', 2),
  (9,  'What is Nigeria''s federal legislature called?', '{"Parliament","Congress","National Assembly","Senate Council"}', 2),
  (10, 'Which body conducts elections in Nigeria?', '{"EFCC","INEC","NBC","NIMC"}', 1),
  (11, 'Which agency fights financial crimes in Nigeria?', '{"ICPC only","DSS","EFCC","NDLEA"}', 2),
  (12, 'How long is a presidential term in Nigeria?', '{"3 years","4 years","5 years","6 years"}', 1),
  (13, 'How many terms can a Nigerian president serve?', '{"1","2","3","Unlimited"}', 1),
  (14, 'What colours are on the Nigerian flag?', '{"Green and white","Green and yellow","Green, white and red","White and blue"}', 0),
  (15, 'Who designed the Nigerian flag?', '{"Nnamdi Azikiwe","Taiwo Akinkunmi","Herbert Macaulay","Obafemi Awolowo"}', 1),
  (16, 'Which national anthem did Nigeria readopt in 2024?', '{"Arise, O Compatriots","Nigeria, We Hail Thee","God Bless Nigeria","One Nation Bound"}', 1),
  (17, 'What is the minimum voting age in Nigeria?', '{"16","18","21","25"}', 1),
  (18, 'How many kobo make one naira?', '{"10","50","100","1000"}', 2),
  (19, 'Which river meets the Niger at Lokoja?', '{"Benue","Kaduna","Ogun","Cross River"}', 0),
  (20, 'Who was Nigeria''s first President?', '{"Tafawa Balewa","Nnamdi Azikiwe","Yakubu Gowon","Olusegun Obasanjo"}', 1),
  (21, 'Who was Nigeria''s first Prime Minister?', '{"Abubakar Tafawa Balewa","Ahmadu Bello","Obafemi Awolowo","Nnamdi Azikiwe"}', 0),
  (22, 'How many geopolitical zones does Nigeria have?', '{"4","5","6","8"}', 2),
  (23, 'Which state is known as the "Centre of Excellence"?', '{"Lagos","Ogun","Rivers","Oyo"}', 0),
  (24, 'Which state is known as the "Coal City State"?', '{"Enugu","Kogi","Benue","Anambra"}', 0),
  (25, 'Which state is called the "Home of Peace and Tourism"?', '{"Cross River","Plateau","Ekiti","Kwara"}', 1),
  (26, 'Which state is called the "Treasure Base of the Nation"?', '{"Delta","Bayelsa","Rivers","Akwa Ibom"}', 2),
  (27, 'Which state is called the "Pace Setter State"?', '{"Oyo","Osun","Ondo","Lagos"}', 0),
  (28, 'Which state is called the "Gateway State"?', '{"Lagos","Ogun","Kwara","Niger"}', 1),
  (29, 'On what date is Democracy Day celebrated in Nigeria?', '{"May 29","June 12","October 1","January 15"}', 1),
  (30, 'Nigeria''s current constitution dates from which year?', '{"1979","1989","1999","2011"}', 2),
  (31, 'What is the minimum age to run for President of Nigeria?', '{"30","35","40","45"}', 1),
  (32, 'Who presides over the Nigerian Senate?', '{"The Vice President","The Chief Justice","The Senate President","The Speaker"}', 2);

create table achievements (id text primary key, label text not null, blurb text not null, reward int not null, sort int not null);
insert into achievements values
  ('first_steps',  'Card-carrying citizen', 'Registered in Niger Area.',                    0,     1),
  ('party_member', 'Comrade',               'Joined a political party.',                    500,   2),
  ('party_founder','Founding father',       'Registered your own party with INEC.',         2000,  3),
  ('first_vote',   'Inked finger',          'Voted in an election.',                        500,   4),
  ('candidate',    'On the ballot',         'Declared candidacy for office.',               1000,  5),
  ('won_lg',       'Chairman!',             'Won a local government election.',            5000,  6),
  ('won_sen',      'Distinguished Senator', 'Won a Senate seat.',                           10000, 7),
  ('won_gov',      'His Excellency',        'Won a governorship.',                          20000, 8),
  ('won_pres',     'Commander-in-Chief',    'Won the presidency.',                          50000, 9),
  ('streak7',      'Faithful citizen',      'Signed in 7 days in a row.',                   3000,  10),
  ('streak30',     'Pillar of the nation',  'Signed in 30 days in a row.',                  15000, 11),
  ('homeowner',    'Landlord',              'Moved out of the face-me-I-face-you.',         500,   12),
  ('mansion',      'Maitama money',         'Bought a mansion in Maitama.',                 5000,  13),
  ('entrepreneur', 'Entrepreneur',          'Opened your first business.',                  500,   14),
  ('oil_baron',    'Oil baron',             'Opened a filling station.',                    3000,  15),
  ('hustler',      'Hustler',               'Completed 50 hustles.',                        3000,  16),
  ('scholar',      'Scholar',               'Answered 10 trivia questions correctly.',      2000,  17),
  ('town_crier',   'Town crier',            'Posted 25 times on Gist.',                     1000,  18),
  ('builder',      'Builder',               'Commissioned a public project in office.',     2000,  19),
  ('perfect_day',  'Perfect day',           'Finished every daily task in one day.',        0,     20);

create table citizen_achievements (
  citizen_id uuid not null references citizens on delete cascade,
  achievement_id text not null references achievements,
  earned_at timestamptz not null default now(),
  primary key (citizen_id, achievement_id)
);

-- Secret ballot: nobody can read who voted for whom, only their own row.
create table votes (
  election_id uuid not null references elections on delete cascade,
  voter_id uuid not null references citizens on delete cascade,
  candidate_id uuid not null references citizens,
  cast_at timestamptz not null default now(),
  primary key (election_id, voter_id)
);

-- Gist: 'national' or a party id as the channel.
create table posts (
  id bigserial primary key,
  author_id uuid not null references citizens on delete cascade,
  channel text not null,
  body text not null check (char_length(body) between 1 and 280),
  created_at timestamptz not null default now(),
  deleted boolean not null default false
);
create index posts_channel_idx on posts (channel, id desc);

create table admins (user_id uuid primary key references auth.users on delete cascade);

create table sanctions (
  id bigserial primary key,
  citizen_id uuid not null references citizens on delete cascade,
  admin_id uuid references auth.users,
  kind text not null,
  reason text not null,
  amount bigint,
  until timestamptz,
  created_at timestamptz not null default now()
);

alter table hustles enable row level security;
alter table trivia enable row level security;
alter table achievements enable row level security;
alter table citizen_achievements enable row level security;
alter table votes enable row level security;
alter table posts enable row level security;
alter table admins enable row level security;
alter table sanctions enable row level security;

create policy read_all on hustles for select to authenticated using (true);
create policy read_all on achievements for select to authenticated using (true);
create policy read_all on citizen_achievements for select to authenticated using (true);
create policy read_own on votes for select to authenticated using (voter_id = auth.uid());
create policy read_own on sanctions for select to authenticated using (citizen_id = auth.uid());
create policy read_channel on posts for select to authenticated using (
  not deleted and (channel = 'national'
    or exists (select 1 from party_members m where m.citizen_id = auth.uid() and m.party_id::text = posts.channel)));
-- trivia and admins: no client access.

-- ---------- Helpers ----------
create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where user_id = auth.uid())
$$;

create or replace function _me() returns citizens
language plpgsql security definer set search_path = public as $$
declare c citizens;
begin
  if auth.uid() is null then perform _fail('Sign in first.'); end if;
  select * into c from citizens where id = auth.uid() for update;
  if not found then perform _fail('Register as a citizen first.'); end if;
  if c.banned then perform _fail('This account has been banned: ' || coalesce(c.ban_reason, 'breaking the rules') || '.'); end if;
  if c.suspended_until > now() then
    perform _fail('This account is suspended until ' || to_char(c.suspended_until at time zone 'Africa/Lagos', 'DD Mon HH24:MI') || ' WAT.');
  end if;
  return c;
end $$;

create or replace function _use_energy(p_citizen uuid, p_n int) returns void
language plpgsql security definer set search_path = public as $$
begin
  update citizens set energy = 8, energy_day = game_day()
   where id = p_citizen and energy_day < game_day();
  update citizens set energy = energy - p_n where id = p_citizen and energy >= p_n;
  if not found then perform _fail('No energy left today. Come back tomorrow.'); end if;
end $$;

-- Grants an achievement once, pays its reward, and announces the big ones.
create or replace function _award(p_citizen uuid, p_id text) returns void
language plpgsql security definer set search_path = public as $$
declare a achievements; n text;
begin
  insert into citizen_achievements (citizen_id, achievement_id) values (p_citizen, p_id) on conflict do nothing;
  if not found then return; end if;
  select * into a from achievements where id = p_id;
  if a.reward > 0 then perform _move(p_citizen, 'coins', a.reward, 'achievement', p_id, 'ach:' || p_citizen || ':' || p_id); end if;
  if p_id in ('party_founder','won_sen','won_gov','won_pres','streak30','mansion','oil_baron') then
    select display_name into n from citizens where id = p_citizen;
    perform _news(n || ' earns the "' || a.label || '" badge.');
  end if;
end $$;

-- ---------- Citizenship and the daily loop ----------
create or replace function register_citizen(p_name text, p_lga text) returns void
language plpgsql security definer set search_path = public as $$
declare s text;
begin
  if auth.uid() is null then perform _fail('Sign in first.'); end if;
  if exists (select 1 from citizens where id = auth.uid()) then perform _fail('You are already a citizen.'); end if;
  select state_id into s from lgas where id = p_lga;
  if s is null then perform _fail('Unknown local government.'); end if;
  insert into citizens (id, display_name, state_id, lga_id, energy_day, energy, kyc_level, last_seen)
  values (auth.uid(), trim(p_name), s, p_lga, game_day(), 8,
          case when (select playtest from game_clock where id = 1) then 1 else 0 end, now());
  insert into wallets (citizen_id, coins) values (auth.uid(), 0);
  perform _move(auth.uid(), 'coins', 10000, 'welcome_bonus', null, 'welcome:' || auth.uid());
  perform _award(auth.uid(), 'first_steps');
  perform _news(trim(p_name) || ' registers as a citizen of ' || (select name from lgas where id = p_lga) || '.');
end $$;

-- Existing playtesters get topped up to the new 10,000 welcome bonus.
do $$
declare r record;
begin
  for r in select citizen_id from ledger where reason = 'welcome_bonus' and delta = 1500 loop
    perform _move(r.citizen_id, 'coins', 8500, 'welcome_topup', null, 'welcome_topup:' || r.citizen_id);
    insert into citizen_achievements (citizen_id, achievement_id) values (r.citizen_id, 'first_steps') on conflict do nothing;
  end loop;
end $$;

create or replace function touch() returns void
language sql security definer set search_path = public as $$
  update citizens set last_seen = now() where id = auth.uid()
$$;

-- 2,000 a day, plus 3,000 on every 7th day of an unbroken streak.
drop function if exists claim_daily();
create function claim_daily() returns jsonb
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); l daily_limits := _limits(c.id); s int; bonus int := 0;
begin
  if l.claimed then perform _fail('You already claimed today''s bonus.'); end if;
  update daily_limits set claimed = true where citizen_id = c.id and day = l.day;
  s := case when c.last_checkin_day = l.day - 1 then c.streak + 1 else 1 end;
  update citizens set streak = s, best_streak = greatest(best_streak, s), last_checkin_day = l.day where id = c.id;
  perform _move(c.id, 'coins', 2000, 'daily_bonus', null, 'daily:' || c.id || ':' || l.day);
  if s % 7 = 0 then
    bonus := 3000;
    perform _move(c.id, 'coins', bonus, 'streak_bonus', s::text, 'streak:' || c.id || ':' || l.day);
  end if;
  if c.kyc_level >= 1 then
    perform _move(c.id, 'cp', 20, 'daily_checkin', null, 'dailycp:' || c.id || ':' || l.day);
  end if;
  if s >= 7 then perform _award(c.id, 'streak7'); end if;
  if s >= 30 then perform _award(c.id, 'streak30'); end if;
  return jsonb_build_object('streak', s, 'bonus', bonus);
end $$;

-- Web ads: the page starts an ad, and the reward is only paid if 15+ seconds pass on the server clock.
-- When a real web ad network is added, its verified callback replaces finish_ad, as AdMob does on mobile.
create or replace function start_ad() returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); l daily_limits := _limits(c.id);
begin
  if l.ads >= 5 then perform _fail('You have watched all 5 ads for today.'); end if;
  update daily_limits set ad_started_at = now() where citizen_id = c.id and day = l.day;
end $$;

create or replace function finish_ad() returns bigint
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); l daily_limits := _limits(c.id);
begin
  if l.ads >= 5 then perform _fail('You have watched all 5 ads for today.'); end if;
  if l.ad_started_at is null then perform _fail('Start an ad first.'); end if;
  if now() - l.ad_started_at < interval '15 seconds' then perform _fail('Watch the whole ad to get your coins.'); end if;
  update daily_limits set ads = ads + 1, ad_started_at = null where citizen_id = c.id and day = l.day;
  return _move(c.id, 'coins', 400, 'rewarded_ad', null, 'webad:' || c.id || ':' || l.day || ':' || (l.ads + 1));
end $$;

create or replace function credit_ad_reward(p_citizen uuid, p_txn text) returns boolean
language plpgsql security definer set search_path = public as $$
declare l daily_limits;
begin
  insert into ad_rewards (transaction_id, citizen_id, coins) values (p_txn, p_citizen, 400) on conflict do nothing;
  if not found then return false; end if;
  l := _limits(p_citizen);
  if l.ads >= 5 then return false; end if;
  update daily_limits set ads = ads + 1 where citizen_id = p_citizen and day = l.day;
  perform _move(p_citizen, 'coins', 400, 'rewarded_ad', p_txn, 'ad:' || p_txn);
  return true;
end $$;

create or replace function do_hustle(p_hustle text) returns bigint
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); l daily_limits := _limits(c.id); h hustles; pay bigint;
begin
  select * into h from hustles where id = p_hustle;
  if not found then perform _fail('Unknown hustle.'); end if;
  if l.hustles >= 3 then perform _fail('You have done 3 hustles today. Rest and come back tomorrow.'); end if;
  if h.needs_item is not null and not exists (select 1 from citizen_items where citizen_id = c.id and item_id = h.needs_item) then
    perform _fail('You need a ' || (select label from shop_items where id = h.needs_item) || ' for this hustle. Buy one in Household.');
  end if;
  perform _use_energy(c.id, h.energy);
  pay := h.min_pay + floor(random() * (h.max_pay - h.min_pay + 1));
  update daily_limits set hustles = hustles + 1 where citizen_id = c.id and day = l.day;
  update citizens set hustles_total = hustles_total + 1, rep = rep + h.rep_gain where id = c.id;
  perform _move(c.id, 'coins', pay, 'hustle', p_hustle);
  if c.hustles_total + 1 >= 50 then perform _award(c.id, 'hustler'); end if;
  return pay;
end $$;

create or replace function get_trivia() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', t.id, 'question', t.question, 'options', t.options)
    from trivia t
   where t.id = (select id from trivia order by id offset (game_day() % (select count(*) from trivia)) limit 1)
$$;

create or replace function answer_trivia(p_choice int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); l daily_limits := _limits(c.id); t trivia; ok boolean;
begin
  if l.trivia_done then perform _fail('You already answered today''s question.'); end if;
  select * into t from trivia order by id offset (game_day() % (select count(*) from trivia)) limit 1;
  ok := p_choice = t.answer;
  update daily_limits set trivia_done = true where citizen_id = c.id and day = l.day;
  if ok then
    update citizens set trivia_correct = trivia_correct + 1, rep = rep + 0.5 where id = c.id;
    perform _move(c.id, 'coins', 500, 'trivia', t.id::text);
    if c.trivia_correct + 1 >= 10 then perform _award(c.id, 'scholar'); end if;
  end if;
  return jsonb_build_object('correct', ok, 'answer', t.answer);
end $$;

-- Daily checklist: sign in, hustle, trivia, vote or campaign, post on Gist. All five pays 1,500.
create or replace function claim_tasks() returns bigint
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); l daily_limits := _limits(c.id);
begin
  if l.tasks_claimed then perform _fail('You already collected today''s checklist bonus.'); end if;
  if not (l.claimed and l.hustles > 0 and l.trivia_done and l.civic and l.posted) then
    perform _fail('Finish all five daily tasks first.');
  end if;
  update daily_limits set tasks_claimed = true where citizen_id = c.id and day = l.day;
  perform _award(c.id, 'perfect_day');
  return _move(c.id, 'coins', 1500, 'daily_tasks', null, 'tasks:' || c.id || ':' || l.day);
end $$;

-- ---------- Voting ----------
create or replace function cast_vote(p_election uuid, p_candidate uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); e elections; j jurisdictions; l daily_limits;
begin
  select * into e from elections where id = p_election;
  if not found or e.status <> 'open' or e.poll_day <= game_day() then perform _fail('Voting for this race has closed.'); end if;
  select * into j from jurisdictions where key = e.key;
  if (j.type = 'LG' and j.lga_id <> c.lga_id) or (j.type in ('SEN','GOV') and j.state_id <> c.state_id) then
    perform _fail('You can only vote where you are registered.');
  end if;
  if not exists (select 1 from candidates where election_id = p_election and citizen_id = p_candidate) then
    perform _fail('That person is not on the ballot.');
  end if;
  begin
    insert into votes (election_id, voter_id, candidate_id) values (p_election, c.id, p_candidate);
  exception when unique_violation then perform _fail('You already voted in this race.');
  end;
  update candidates set real_votes = real_votes + 1 where election_id = p_election and citizen_id = p_candidate;
  update citizens set votes_cast = votes_cast + 1, rep = rep + 0.3 where id = c.id;
  l := _limits(c.id);
  update daily_limits set civic = true where citizen_id = c.id and day = l.day;
  perform _move(c.id, 'coins', 200, 'voted', e.key);
  perform _award(c.id, 'first_vote');
end $$;

-- ---------- Gist ----------
create or replace function post_gist(p_channel text, p_body text) returns bigint
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); l daily_limits; last timestamptz; today int; pid bigint;
begin
  if c.muted_until > now() then
    perform _fail('You are muted until ' || to_char(c.muted_until at time zone 'Africa/Lagos', 'DD Mon HH24:MI') || ' WAT.');
  end if;
  p_body := trim(p_body);
  if char_length(p_body) < 1 or char_length(p_body) > 280 then perform _fail('Posts must be 1 to 280 characters.'); end if;
  if p_channel <> 'national' and not exists (select 1 from party_members where citizen_id = c.id and party_id::text = p_channel) then
    perform _fail('You can only post in your own party''s room.');
  end if;
  select max(created_at) into last from posts where author_id = c.id;
  if last > now() - interval '20 seconds' then perform _fail('Slow down. Wait a few seconds between posts.'); end if;
  select count(*) into today from posts where author_id = c.id and created_at > now() - interval '24 hours';
  if today >= 40 then perform _fail('You have reached today''s posting limit.'); end if;
  insert into posts (author_id, channel, body) values (c.id, p_channel, p_body) returning id into pid;
  update citizens set posts_total = posts_total + 1 where id = c.id;
  l := _limits(c.id);
  update daily_limits set posted = true where citizen_id = c.id and day = l.day;
  if c.posts_total + 1 >= 25 then perform _award(c.id, 'town_crier'); end if;
  return pid;
end $$;

-- ---------- Leaderboards ----------
create or replace function leaderboard() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'richest', (select coalesce(jsonb_agg(x), '[]') from (
        select c.id, c.display_name as name, w.coins + w.stash as coins, m.party_id
          from citizens c join wallets w on w.citizen_id = c.id left join party_members m on m.citizen_id = c.id
         where not c.banned order by w.coins + w.stash desc limit 20) x),
    'respected', (select coalesce(jsonb_agg(x), '[]') from (
        select c.id, c.display_name as name, floor(c.rep) as rep, m.party_id
          from citizens c left join party_members m on m.citizen_id = c.id
         where not c.banned order by c.rep desc limit 20) x),
    'streaks', (select coalesce(jsonb_agg(x), '[]') from (
        select id, display_name as name, streak from citizens where not banned and streak > 0 order by streak desc limit 20) x),
    'parties', (select coalesce(jsonb_agg(x), '[]') from (
        select p.id, p.name, p.abbr, p.color, count(m.citizen_id) as members,
               (select count(*) from offices o where o.holder_party = p.id) as offices
          from parties p left join party_members m on m.party_id = p.id
         group by p.id order by count(m.citizen_id) desc limit 20) x))
$$;

-- ---------- Existing actions: mark tasks and award badges ----------
create or replace function campaign(p_action text) returns numeric
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); cand candidates; e elections; ru office_rules; a campaign_actions; cost bigint; d numeric; l daily_limits;
begin
  select * into cand from candidates where citizen_id = c.id and votes is null for update;
  if not found then perform _fail('You are not running in any race.'); end if;
  select * into e from elections where id = cand.election_id;
  select ru2.* into ru from office_rules ru2 join jurisdictions j on j.type = ru2.type where j.key = e.key;
  select * into a from campaign_actions where id = p_action;
  if not found then perform _fail('Unknown campaign action.'); end if;
  if c.rep < a.need_rep then perform _fail('The palace says come back when you are better known.'); end if;
  cost := a.base_cost * ru.cost_mult;
  if cand.spent + cost > ru.spend_cap then
    perform _fail(format('That would break the %s-coin spending limit for this race.', ru.spend_cap));
  end if;
  perform _use_energy(c.id, a.energy);
  if cost > 0 then perform _move(c.id, 'stash', -cost, 'campaign:' || p_action, e.key); end if;
  d := a.pop_min + random() * (a.pop_max - a.pop_min);
  if p_action = 'influencers' and random() < 0.2 then d := -4; end if;
  update candidates set popularity = least(100, greatest(0, popularity + d)), spent = spent + cost
   where election_id = cand.election_id and citizen_id = c.id;
  update citizens set scandal = scandal + a.scandal,
                      integrity = least(100, greatest(0, integrity + a.integrity)),
                      rep = rep + a.rep_gain
   where id = c.id;
  l := _limits(c.id);
  update daily_limits set civic = true where citizen_id = c.id and day = l.day;
  return d;
end $$;

create or replace function declare_candidacy(p_key text) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); j jurisdictions; ru office_rules; e elections; m party_members; pop numeric;
begin
  select * into j from jurisdictions where key = p_key;
  if not found then perform _fail('That office does not exist.'); end if;
  if (j.type = 'LG' and j.lga_id <> c.lga_id) or (j.type in ('SEN', 'GOV') and j.state_id <> c.state_id) then
    perform _fail('You can only run where you are registered to vote.');
  end if;
  if c.kyc_level < 1 then perform _fail('Verify your phone number to run for office.'); end if;
  select * into m from party_members where citizen_id = c.id;
  if not found then perform _fail('You need a party ticket first.'); end if;
  select * into ru from office_rules where type = j.type;
  if c.rep < ru.min_rep then perform _fail(format('You need reputation %s to run for %s.', ru.min_rep, ru.title)); end if;
  select * into e from elections where key = p_key and status = 'open';
  if not found or e.poll_day <= game_day() then perform _fail('Nominations for this race are closed.'); end if;
  pop := 8 + _status(c.id) * 0.6 + least(c.rep, 60) * 0.4
       + case when exists (select 1 from offices where key = p_key and holder_id = c.id) then _approval(p_key) * 0.4 else 0 end;
  perform _move(c.id, 'stash', -ru.fee, 'nomination_fee', p_key);
  begin
    insert into candidates (election_id, citizen_id, party_id, popularity) values (e.id, c.id, m.party_id, pop);
  exception when unique_violation then
    perform _fail('Either your party already has a candidate in this race, or you are running elsewhere.');
  end;
  perform _award(c.id, 'candidate');
  perform _news(c.display_name || ' picks the ' || (select abbr from parties where id = m.party_id)
                || ' ticket for ' || _place(p_key) || '.');
end $$;

create or replace function join_party(p_party uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); pname text;
begin
  if exists (select 1 from party_members where citizen_id = c.id) then perform _fail('Leave your current party first.'); end if;
  select name into pname from parties where id = p_party;
  if pname is null then perform _fail('That party does not exist.'); end if;
  perform _move(c.id, 'coins', -200, 'party_dues', p_party::text);
  insert into party_members (citizen_id, party_id, joined_day) values (c.id, p_party, game_day());
  perform _award(c.id, 'party_member');
  perform _news(c.display_name || ' joins the ' || pname || '.');
end $$;

create or replace function create_party(p_name text, p_abbr text, p_color text) returns uuid
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); pid uuid;
begin
  if exists (select 1 from party_members where citizen_id = c.id) then perform _fail('Leave your current party first.'); end if;
  if c.kyc_level < 1 then perform _fail('Verify your phone number to register a party.'); end if;
  perform _move(c.id, 'coins', -5000, 'party_registration');
  begin
    insert into parties (name, abbr, color, chair_id) values (trim(p_name), upper(trim(p_abbr)), p_color, c.id)
    returning id into pid;
  exception when unique_violation then perform _fail('A party with that name or abbreviation already exists.');
            when check_violation  then perform _fail('Use a 3-40 letter name, a 2-6 letter abbreviation and a hex colour.');
  end;
  insert into party_members (citizen_id, party_id, role, joined_day) values (c.id, pid, 'chair', game_day());
  perform _award(c.id, 'party_member');
  perform _award(c.id, 'party_founder');
  perform _news('INEC registers a new party, the ' || trim(p_name) || ', led by ' || c.display_name || '.');
  return pid;
end $$;

create or replace function buy_item(p_item text) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); it shop_items; have int;
begin
  select * into it from shop_items where id = p_item;
  if not found then perform _fail('That item is not for sale.'); end if;
  select qty into have from citizen_items where citizen_id = c.id and item_id = p_item;
  have := coalesce(have, 0);
  if have >= it.max_qty then perform _fail('You already have the maximum of this.'); end if;
  if it.requires is not null and not exists (select 1 from citizen_items where citizen_id = c.id and item_id = it.requires) then
    perform _fail('Buy the previous upgrade first.');
  end if;
  perform _move(c.id, 'coins', -it.cost, 'purchase_item', p_item);
  insert into citizen_items (citizen_id, item_id, qty) values (c.id, p_item, 1)
  on conflict (citizen_id, item_id) do update set qty = citizen_items.qty + 1;
  if it.kind = 'house' then perform _award(c.id, 'homeowner'); end if;
  if p_item = 'house5' then perform _award(c.id, 'mansion'); end if;
  if it.kind = 'business' then perform _award(c.id, 'entrepreneur'); end if;
  if p_item = 'station' then perform _award(c.id, 'oil_baron'); end if;
end $$;

-- ---------- Tick: real votes count, badges for winners and builders ----------
create or replace function _resolve_election(p_election uuid, p_day int) returns void
language plpgsql security definer set search_path = public as $$
declare e elections; j jurisdictions; ru office_rules; n int; v_turnout bigint; win candidates; wname text;
begin
  select * into e from elections where id = p_election for update;
  select * into j from jurisdictions where key = e.key;
  select * into ru from office_rules where type = j.type;
  select count(*) into n from candidates where election_id = e.id;

  if n = 0 then
    update elections set status = 'closed', turnout = 0 where id = e.id;
    update offices set holder_id = null, holder_party = null, term_ends_day = p_day + 14 where key = e.key;
    insert into elections (key, poll_day) values (e.key, p_day + 14);
    insert into news (day, body) values (p_day, 'No candidate filed for ' || _place(e.key)
      || '. A caretaker committee takes over until fresh polls in 14 days.');
    return;
  end if;

  v_turnout := floor((ru.voters_min + random() * (ru.voters_max - ru.voters_min)) * (0.28 + random() * 0.14));

  -- Each real player's vote is worth 8 popularity points: the people decide close races.
  with w as (
    select citizen_id,
           greatest(1, popularity + real_votes * 8
                       + _party_strength(party_id) * case when j.type = 'PRES' then 0.6 else 0.35 end
                       + random() * 14) as wt
      from candidates where election_id = e.id),
  s as (select sum(wt) as tot from w)
  update candidates c set votes = round(w.wt / s.tot * v_turnout)
    from w, s
   where c.election_id = e.id and c.citizen_id = w.citizen_id;

  select * into win from candidates where election_id = e.id order by votes desc, popularity desc limit 1;
  select display_name into wname from citizens where id = win.citizen_id;

  update elections set status = 'closed', turnout = v_turnout where id = e.id;
  update offices set holder_id = null, holder_party = null where holder_id = win.citizen_id and key <> e.key;
  update offices set holder_id = win.citizen_id, holder_party = win.party_id, term_ends_day = p_day + ru.term_days
   where key = e.key;
  update jurisdictions set mood = 10, last_salary_day = p_day where key = e.key;
  update citizens set offices_held = offices_held + 1, rep = rep + 8 where id = win.citizen_id;
  perform _move(win.citizen_id, 'cp', 500, 'election_win', e.key, 'win:' || e.id);
  perform _award(win.citizen_id, case j.type when 'LG' then 'won_lg' when 'SEN' then 'won_sen' when 'GOV' then 'won_gov' else 'won_pres' end);
  insert into elections (key, poll_day) values (e.key, p_day + ru.term_days);
  insert into news (day, body) values (p_day, 'INEC declares ' || wname || ' ('
    || (select abbr from parties where id = win.party_id) || ') winner: ' || _place(e.key)
    || ', with ' || to_char(win.votes, 'FM999,999,999') || ' votes.');
end $$;

create or replace function advance_day() returns int
language plpgsql security definer set search_path = public as $$
declare d int; r record;
begin
  update game_clock set day = day + 1 where id = 1 returning day into d;

  for r in select * from projects where not done and ready_day <= d loop
    execute format('update jurisdictions set %1$I = least(100, %1$I + $1), mood = mood + 3 where key = $2', r.stat)
      using r.gain, r.key;
    update projects set done = true where id = r.id;
    if r.started_by is not null then
      update citizens set rep = rep + 0.3 where id = r.started_by;
      perform _award(r.started_by, 'builder');
    end if;
    insert into news (day, body) values (d, 'Commissioned: a new ' || r.stat || ' project. ' || _place(r.key) || '.');
  end loop;

  update jurisdictions set mood = mood * 0.9,
    roads = greatest(0, roads - 0.3), power = greatest(0, power - 0.3), health = greatest(0, health - 0.3),
    edu = greatest(0, edu - 0.3), security = greatest(0, security - 0.3), economy = greatest(0, economy - 0.3)
  where true;

  for r in select o.key, o.holder_id, ru.salary
             from offices o join jurisdictions j on j.key = o.key join office_rules ru on ru.type = j.type
            where o.holder_id is not null loop
    perform _move(r.holder_id, 'coins', r.salary, 'salary', r.key, 'salary:' || r.key || ':' || d);
    if _approval(r.key) >= 60 then
      perform _move(r.holder_id, 'cp', 50, 'good_governance', r.key, 'gg:' || r.key || ':' || d);
      update citizens set rep = rep + 0.3 where id = r.holder_id;
    end if;
  end loop;

  for r in select ci.citizen_id, sum(ci.qty * s.daily_income)::bigint as inc
             from citizen_items ci join shop_items s on s.id = ci.item_id
            where s.daily_income > 0 group by ci.citizen_id loop
    perform _move(r.citizen_id, 'coins', r.inc, 'business_income', null, 'biz:' || r.citizen_id || ':' || d);
  end loop;

  update citizens c set rep = rep + 0.2 from daily_limits l
   where l.citizen_id = c.id and l.day = d - 1 and l.claimed;
  update citizens set scandal = greatest(0, scandal - 0.5) where scandal > 0;

  if d % 30 = 0 then
    update jurisdictions j set treasury = treasury + round(ru.alloc * (select alloc_boost from game_clock where id = 1))
      from office_rules ru where ru.type = j.type;
    update game_clock set alloc_boost = 1 where id = 1;
    update jurisdictions set mood = mood - 15
     where key in (select key from offices where holder_id is not null) and d - last_salary_day > 30;
    insert into news (day, body) values (d, 'FAAC shares the monthly federation allocation.');
  end if;

  for r in select id from elections where status = 'open' and poll_day <= d loop
    perform _resolve_election(r.id, d);
  end loop;

  for r in select id, scandal from citizens where scandal > 40 loop
    if random() < (r.scandal - 40) / 180 then perform _efcc_raid(r.id, d); end if;
  end loop;

  return d;
end $$;

-- ---------- Owner dashboard ----------
create or replace function _admin_only() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then perform _fail('Owner access only.'); end if;
end $$;

create or replace function admin_dashboard() returns jsonb
language plpgsql security definer set search_path = public as $$
declare tz text := 'Africa/Lagos'; today date := (now() at time zone 'Africa/Lagos')::date; out jsonb;
begin
  perform _admin_only();
  select jsonb_build_object(
    'game', (select jsonb_build_object('day', day, 'playtest', playtest) from game_clock where id = 1),
    'players', jsonb_build_object(
       'total',         (select count(*) from citizens),
       'today',         (select count(*) from citizens where (created_at at time zone tz)::date = today),
       'week',          (select count(*) from citizens where created_at > now() - interval '7 days'),
       'active_today',  (select count(distinct citizen_id) from ledger where (created_at at time zone tz)::date = today),
       'active_week',   (select count(distinct citizen_id) from ledger where created_at > now() - interval '7 days'),
       'online_now',    (select count(*) from citizens where last_seen > now() - interval '10 minutes'),
       'banned',        (select count(*) from citizens where banned),
       'suspended',     (select count(*) from citizens where suspended_until > now()),
       'muted',         (select count(*) from citizens where muted_until > now())),
    'signups_30d', (select coalesce(jsonb_agg(jsonb_build_object('d', d, 'n', n) order by d), '[]') from (
        select g::date as d, (select count(*) from citizens c where (c.created_at at time zone tz)::date = g::date) as n
          from generate_series(today - 29, today, interval '1 day') g) x),
    'active_14d', (select coalesce(jsonb_agg(jsonb_build_object('d', d, 'n', n) order by d), '[]') from (
        select g::date as d, (select count(distinct citizen_id) from ledger l where (l.created_at at time zone tz)::date = g::date) as n
          from generate_series(today - 13, today, interval '1 day') g) x),
    'economy', jsonb_build_object(
       'coins',      (select coalesce(sum(coins), 0) from wallets),
       'stash',      (select coalesce(sum(stash), 0) from wallets),
       'cp',         (select coalesce(sum(cp), 0) from wallets),
       'bought',     (select coalesce(sum(purchased_total), 0) from wallets),
       'sources_today', (select coalesce(jsonb_agg(jsonb_build_object('reason', reason, 'total', t) order by t desc), '[]') from (
            select reason, sum(delta) t from ledger where cur = 'coins' and delta > 0 and (created_at at time zone tz)::date = today group by reason) x),
       'sinks_today',   (select coalesce(jsonb_agg(jsonb_build_object('reason', reason, 'total', t) order by t), '[]') from (
            select reason, sum(delta) t from ledger where cur in ('coins','stash') and delta < 0 and reason not in ('to_stash','from_stash')
               and (created_at at time zone tz)::date = today group by reason) x)),
    'revenue', jsonb_build_object(
       'paid_count',  (select count(*) from purchases where status = 'paid'),
       'total_naira', (select coalesce(sum(kobo), 0) / 100 from purchases where status = 'paid'),
       'month_naira', (select coalesce(sum(kobo), 0) / 100 from purchases where status = 'paid' and paid_at > now() - interval '30 days'),
       'pending',     (select count(*) from purchases where status = 'pending')),
    'redemptions', jsonb_build_object(
       'pending', (select count(*) from redemptions where status = 'pending'),
       'pending_naira', (select coalesce(sum(naira), 0) from redemptions where status = 'pending'),
       'paid_naira', (select coalesce(sum(naira), 0) from redemptions where status = 'paid')),
    'engagement', jsonb_build_object(
       'posts_today',  (select count(*) from posts where (created_at at time zone tz)::date = today),
       'votes_total',  (select count(*) from votes),
       'hustles_today',(select count(*) from ledger where reason = 'hustle' and (created_at at time zone tz)::date = today),
       'trivia_today', (select count(*) from daily_limits where day = game_day() and trivia_done),
       'streak_7plus', (select count(*) from citizens where streak >= 7),
       'parties',      (select count(*) from parties),
       'offices_held', (select count(*) from offices where holder_id is not null),
       'offices_total',(select count(*) from offices)),
    'upcoming', (select coalesce(jsonb_agg(x order by x.poll_day), '[]') from (
        select e.key, _place(e.key) as place, e.poll_day, (select count(*) from candidates c where c.election_id = e.id) as candidates,
               (select coalesce(sum(real_votes), 0) from candidates c where c.election_id = e.id) as votes
          from elections e where e.status = 'open' order by e.poll_day, e.key limit 12) x),
    'flags', (select coalesce(jsonb_agg(x), '[]') from (
        select c.id, c.display_name as name, 'Earned ' || sum(l.delta) || ' coins today outside purchases, salary and business' as why
          from ledger l join citizens c on c.id = l.citizen_id
         where l.cur = 'coins' and l.delta > 0 and (l.created_at at time zone tz)::date = today
           and l.reason not in ('coin_purchase','salary','business_income','welcome_bonus','welcome_topup','achievement','from_stash')
         group by c.id having sum(l.delta) > 12000
        union all
        select c.id, c.display_name, 'Received ' || sum(l.delta) || ' coins in gifts this week'
          from ledger l join citizens c on c.id = l.citizen_id
         where l.reason = 'gift_in' and l.created_at > now() - interval '7 days'
         group by c.id having sum(l.delta) >= 10000
        union all
        select id, display_name, 'Scandal score ' || round(scandal) from citizens where scandal >= 60
        union all
        select null, null, count(*) || ' accounts registered in the last hour'
          from citizens where created_at > now() - interval '1 hour' having count(*) >= 20) x)
  ) into out;
  return out;
end $$;

create or replace function admin_players(p_search text default '', p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
begin
  perform _admin_only();
  return (select coalesce(jsonb_agg(x), '[]') from (
    select c.id, c.display_name as name, u.email, s.name as state, g.name as lga, c.created_at, c.last_seen,
           w.coins, w.stash, w.cp, floor(c.rep) as rep, c.streak, c.banned, c.suspended_until, c.muted_until,
           c.scandal, p.abbr as party, o.key as office
      from citizens c
      join auth.users u on u.id = c.id
      join wallets w on w.citizen_id = c.id
      join states s on s.id = c.state_id
      join lgas g on g.id = c.lga_id
      left join party_members m on m.citizen_id = c.id
      left join parties p on p.id = m.party_id
      left join offices o on o.holder_id = c.id
     where p_search = '' or c.display_name ilike '%' || p_search || '%' or u.email ilike '%' || p_search || '%'
     order by c.created_at desc limit least(p_limit, 500)) x);
end $$;

create or replace function admin_player(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
begin
  perform _admin_only();
  return jsonb_build_object(
    'citizen', (select to_jsonb(c) || jsonb_build_object('email', u.email, 'signed_in_at', u.last_sign_in_at)
                  from citizens c join auth.users u on u.id = c.id where c.id = p_id),
    'wallet', (select to_jsonb(w) from wallets w where citizen_id = p_id),
    'ledger', (select coalesce(jsonb_agg(x order by x.id desc), '[]') from (select * from ledger where citizen_id = p_id order by id desc limit 60) x),
    'sanctions', (select coalesce(jsonb_agg(x order by x.id desc), '[]') from sanctions x where citizen_id = p_id),
    'achievements', (select coalesce(jsonb_agg(achievement_id), '[]') from citizen_achievements where citizen_id = p_id),
    'posts', (select coalesce(jsonb_agg(x order by x.id desc), '[]') from (select * from posts where author_id = p_id order by id desc limit 20) x));
end $$;

-- kinds: warn, mute, unmute, suspend, unsuspend, ban, unban, fine, grant, reset_rep, remove_office, disqualify
create or replace function admin_sanction(p_target uuid, p_kind text, p_reason text, p_days int default null, p_amount bigint default null)
returns void
language plpgsql security definer set search_path = public as $$
declare n text; until_at timestamptz := case when p_days is not null then now() + make_interval(days => p_days) end;
begin
  perform _admin_only();
  select display_name into n from citizens where id = p_target;
  if n is null then perform _fail('Player not found.'); end if;
  if coalesce(trim(p_reason), '') = '' then perform _fail('Give a reason. The player will see it.'); end if;
  case p_kind
    when 'warn' then null;
    when 'mute' then update citizens set muted_until = coalesce(until_at, now() + interval '1 day') where id = p_target;
    when 'unmute' then update citizens set muted_until = null where id = p_target;
    when 'suspend' then update citizens set suspended_until = coalesce(until_at, now() + interval '3 days') where id = p_target;
    when 'unsuspend' then update citizens set suspended_until = null where id = p_target;
    when 'ban' then
      update citizens set banned = true, ban_reason = p_reason where id = p_target;
      update offices set holder_id = null, holder_party = null where holder_id = p_target;
      delete from candidates where citizen_id = p_target and votes is null;
    when 'unban' then update citizens set banned = false, ban_reason = null where id = p_target;
    when 'fine' then
      if coalesce(p_amount, 0) <= 0 then perform _fail('Enter the fine amount.'); end if;
      perform _move(p_target, 'coins', -least(p_amount, (select coins from wallets where citizen_id = p_target)), 'admin_fine', p_reason);
    when 'grant' then
      if coalesce(p_amount, 0) <= 0 then perform _fail('Enter the amount to grant.'); end if;
      perform _move(p_target, 'coins', p_amount, 'admin_grant', p_reason);
    when 'reset_rep' then update citizens set rep = 0 where id = p_target;
    when 'remove_office' then update offices set holder_id = null, holder_party = null where holder_id = p_target;
    when 'disqualify' then delete from candidates where citizen_id = p_target and votes is null;
    else perform _fail('Unknown sanction.');
  end case;
  insert into sanctions (citizen_id, admin_id, kind, reason, amount, until)
  values (p_target, auth.uid(), p_kind, p_reason, p_amount, until_at);
  if p_kind in ('ban', 'remove_office', 'disqualify') then
    perform _news('Niger Area authorities sanction ' || n || ': ' || p_reason);
  end if;
end $$;

create or replace function admin_sanctions_log(p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  return (select coalesce(jsonb_agg(x order by x.id desc), '[]') from (
    select s.*, c.display_name as name from sanctions s join citizens c on c.id = s.citizen_id order by s.id desc limit p_limit) x);
end $$;

create or replace function admin_redemptions() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  return (select coalesce(jsonb_agg(x order by x.id), '[]') from (
    select r.*, c.display_name as name, c.kyc_level from redemptions r join citizens c on c.id = r.citizen_id
     where r.status = 'pending' order by r.id limit 200) x);
end $$;

-- Rejecting refunds the civic points.
create or replace function admin_resolve_redemption(p_id bigint, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
declare r redemptions;
begin
  perform _admin_only();
  select * into r from redemptions where id = p_id for update;
  if not found or r.status <> 'pending' then perform _fail('That request is no longer pending.'); end if;
  if p_approve then
    update redemptions set status = 'paid' where id = p_id;
  else
    update redemptions set status = 'rejected' where id = p_id;
    perform _move(r.citizen_id, 'cp', r.cp, 'redemption_refund', p_id::text, 'refund:' || p_id);
  end if;
end $$;

create or replace function admin_posts(p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  return (select coalesce(jsonb_agg(x order by x.id desc), '[]') from (
    select p.*, c.display_name as name, coalesce(pa.abbr, 'National') as room
      from posts p join citizens c on c.id = p.author_id left join parties pa on pa.id::text = p.channel
     order by p.id desc limit p_limit) x);
end $$;

create or replace function admin_delete_post(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  update posts set deleted = true where id = p_id;
end $$;

create or replace function admin_set_playtest(p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  update game_clock set playtest = p_on where id = 1;
end $$;

create or replace function admin_broadcast(p_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  if coalesce(trim(p_body), '') = '' then perform _fail('Write the announcement first.'); end if;
  perform _news('📢 ' || trim(p_body));
end $$;

create or replace function admin_advance_day() returns int
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  return advance_day();
end $$;

-- ---------- Grants ----------
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function
  game_day(), is_admin(), register_citizen(text, text), touch(), claim_daily(), start_ad(), finish_ad(),
  do_hustle(text), get_trivia(), answer_trivia(int), claim_tasks(), cast_vote(uuid, uuid), post_gist(text, text),
  leaderboard(), stash_coins(bigint), unstash_coins(bigint), gift_coins(uuid, bigint), redeem_cp(bigint, text),
  buy_item(text), join_party(uuid), create_party(text, text, text), leave_party(), declare_candidacy(text),
  campaign(text), withdraw_candidacy(), start_project(text), town_hall(), pay_salaries(), playtest_advance_day(),
  admin_dashboard(), admin_players(text, int), admin_player(uuid), admin_sanction(uuid, text, text, int, bigint),
  admin_sanctions_log(int), admin_redemptions(), admin_resolve_redemption(bigint, boolean), admin_posts(int),
  admin_delete_post(bigint), admin_set_playtest(boolean), admin_broadcast(text), admin_advance_day()
to authenticated;
