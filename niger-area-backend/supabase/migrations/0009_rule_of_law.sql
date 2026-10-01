-- Niger Area: power and the voter's card.
--   * Leaders decide: decrees with real trade-offs, and the power to order arrests.
--   * Detained citizens can do nothing except post bail.
--   * Every citizen holds a PVC with a VIN, and must revalidate it for each election,
--     at least 2 days before polling day, to vote or stand.
--   * One citizen per IP address (owner can allow shared IPs).
--   * Nobody skips days: the clock only moves at midnight WAT.

drop function if exists playtest_advance_day();
drop function if exists admin_advance_day();

alter table citizens add column vin text unique;
alter table citizens add column signup_ip text;
alter table citizens add column last_ip text;
alter table citizens add column detained_until timestamptz;
alter table citizens add column detained_by uuid references citizens;
alter table citizens add column detained_charge text;
alter table citizens add column last_arrested_at timestamptz;
update citizens set vin = upper(substr(replace(id::text, '-', ''), 1, 19)) where vin is null;

create table election_registrations (
  election_id uuid not null references elections on delete cascade,
  citizen_id  uuid not null references citizens on delete cascade,
  registered_day int not null,
  primary key (election_id, citizen_id)
);

create table ip_allowlist (ip text primary key, note text, added_at timestamptz not null default now());

create table arrests (
  id bigserial primary key,
  by_id uuid references citizens,
  by_office text,
  target_id uuid not null references citizens on delete cascade,
  charge text not null,
  day int not null,
  created_at timestamptz not null default now(),
  released_at timestamptz,
  released_how text
);

create table decrees (
  id text primary key,
  office office_type not null,
  label text not null,
  blurb text not null,
  effects jsonb not null,          -- stat deltas, e.g. {"security": 6, "economy": -4, "mood": -3}
  treasury_delta bigint not null default 0,
  cooldown_days int not null default 7
);
insert into decrees values
  ('okada_ban',     'LG',   'Ban okada on major roads',          'Fewer robberies on bikes. Riders lose their daily bread.', '{"security":6,"economy":-4,"mood":-3}', 0, 7),
  ('market_levy',   'LG',   'Impose a market levy',              'Fills the treasury. Traders will grumble.',               '{"economy":-3,"mood":-4}', 4000, 7),
  ('sanitation',    'LG',   'Monthly environmental sanitation',  'Last Saturday of the month: no movement until 10am.',     '{"health":5,"economy":-2,"mood":-1}', 0, 7),
  ('free_clinic',   'LG',   'Free maternal healthcare',          'Mothers deliver for free at primary health centres.',     '{"health":8,"mood":4}', -5000, 7),
  ('const_project', 'SEN',  'Attract a constituency project',    'Boreholes and solar streetlights with your name on them.','{"roads":4,"power":4,"mood":3}', -5000, 7),
  ('state_police',  'SEN',  'Sponsor the state police bill',     'Popular at home. Some in Abuja won''t like it.',          '{"security":6,"mood":2}', 0, 7),
  ('curfew',        'GOV',  'Declare a dusk-to-dawn curfew',     'Security improves. Night markets shut down.',             '{"security":10,"economy":-6,"mood":-5}', 0, 7),
  ('free_edu',      'GOV',  'Free education to secondary level', 'Expensive, and parents will love you.',                   '{"edu":10,"mood":6}', -20000, 7),
  ('ghost_workers', 'GOV',  'Sack ghost workers',                'Clean the payroll. Unions will march.',                   '{"economy":-1,"mood":-2}', 15000, 7),
  ('agric_loans',   'GOV',  'Agricultural loans for farmers',    'Tractors, fertiliser and soft loans.',                    '{"economy":8,"mood":3}', -15000, 7),
  ('fuel_subsidy',  'PRES', 'Remove fuel subsidy',               'Huge savings. Pump prices triple overnight.',             '{"economy":-5,"mood":-12}', 200000, 14),
  ('close_borders', 'PRES', 'Close the land borders',            'Stops smuggling. Rice prices climb.',                     '{"security":6,"economy":-4,"mood":-3}', 0, 14),
  ('min_wage',      'PRES', 'Raise the minimum wage',            'Workers celebrate. Governors ask where the money is.',    '{"economy":3,"mood":10}', -100000, 14),
  ('power_reform',  'PRES', 'Unbundle the power sector',         'Maybe, just maybe, constant light.',                      '{"power":12,"mood":2}', -80000, 14);

create table decree_log (
  id bigserial primary key,
  key text not null references jurisdictions,
  decree_id text not null references decrees,
  citizen_id uuid references citizens,
  day int not null,
  created_at timestamptz not null default now()
);

alter table election_registrations enable row level security;
alter table ip_allowlist enable row level security;
alter table arrests enable row level security;
alter table decrees enable row level security;
alter table decree_log enable row level security;
create policy read_own on election_registrations for select to authenticated using (citizen_id = auth.uid());
create policy read_all on arrests for select to authenticated using (true);
create policy read_all on decrees for select to authenticated using (true);
create policy read_all on decree_log for select to authenticated using (true);

-- ---------- Helpers ----------
create or replace function _client_ip() returns text
language plpgsql stable set search_path = public as $$
declare h json;
begin
  begin h := current_setting('request.headers', true)::json; exception when others then return null; end;
  if h is null then return null; end if;
  return nullif(trim(coalesce(h->>'cf-connecting-ip', h->>'x-real-ip', split_part(h->>'x-forwarded-for', ',', 1))), '');
end $$;

-- Detained citizens are blocked from every action that goes through _me().
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
  if c.detained_until > now() then
    perform _fail('You are in police custody until ' || to_char(c.detained_until at time zone 'Africa/Lagos', 'DD Mon HH24:MI')
                  || ' WAT on a charge of ' || coalesce(c.detained_charge, 'unknown') || '. Post bail to be released early.');
  end if;
  return c;
end $$;

create or replace function _rank(p_type office_type) returns int
language sql immutable as $$ select case p_type when 'LG' then 1 when 'SEN' then 2 when 'GOV' then 3 else 4 end $$;

-- ---------- Registration (one per IP) and presence ----------
create or replace function register_citizen(p_name text, p_lga text) returns void
language plpgsql security definer set search_path = public as $$
declare s text; v_ip text := _client_ip();
begin
  if auth.uid() is null then perform _fail('Sign in first.'); end if;
  if exists (select 1 from citizens where id = auth.uid()) then perform _fail('You are already a citizen.'); end if;
  select state_id into s from lgas where id = p_lga;
  if s is null then perform _fail('Unknown local government.'); end if;
  if v_ip is not null and not exists (select 1 from ip_allowlist a where a.ip = v_ip)
     and exists (select 1 from citizens where signup_ip = v_ip or last_ip = v_ip) then
    perform _fail('A citizen is already registered from this network. One person, one voter''s card.');
  end if;
  insert into citizens (id, display_name, state_id, lga_id, energy_day, energy, kyc_level, last_seen, signup_ip, last_ip, vin)
  values (auth.uid(), trim(p_name), s, p_lga, game_day(), 8,
          case when (select playtest from game_clock where id = 1) then 1 else 0 end, now(), v_ip, v_ip,
          upper(substr(replace(auth.uid()::text, '-', ''), 1, 19)));
  insert into wallets (citizen_id, coins) values (auth.uid(), 0);
  perform _move(auth.uid(), 'coins', 10000, 'welcome_bonus', null, 'welcome:' || auth.uid());
  perform _award(auth.uid(), 'first_steps');
  perform _news(trim(p_name) || ' collects a PVC in ' || (select name from lgas where id = p_lga) || '.');
end $$;

create or replace function touch() returns void
language sql security definer set search_path = public as $$
  update citizens set last_seen = now(), last_ip = coalesce(_client_ip(), last_ip) where id = auth.uid()
$$;

-- ---------- Voter's card ----------
-- Revalidate your PVC for a specific election. Closes 2 days before polling day.
create or replace function revalidate_card(p_election uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); e elections; j jurisdictions;
begin
  select * into e from elections where id = p_election;
  if not found or e.status <> 'open' then perform _fail('That election is not open.'); end if;
  if game_day() > e.poll_day - 2 then
    perform _fail('Revalidation closed. INEC stops revalidating cards 2 days before polling day.');
  end if;
  select * into j from jurisdictions where key = e.key;
  if (j.type = 'LG' and j.lga_id <> c.lga_id) or (j.type in ('SEN','GOV') and j.state_id <> c.state_id) then
    perform _fail('You can only revalidate for elections where you are registered.');
  end if;
  insert into election_registrations (election_id, citizen_id, registered_day) values (p_election, c.id, game_day())
  on conflict do nothing;
  if not found then perform _fail('Your card is already valid for this election.'); end if;
  update citizens set rep = rep + 0.1 where id = c.id;
end $$;

create or replace function _require_card(p_citizen uuid, p_election uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from election_registrations where election_id = p_election and citizen_id = p_citizen) then
    perform _fail('Your voter''s card is not valid for this election. Revalidate it at least 2 days before polling day.');
  end if;
end $$;

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
  perform _require_card(c.id, p_election);
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
  perform _require_card(c.id, e.id);
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

-- ---------- Leaders decide ----------
create or replace function make_decree(p_decree text) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); k text := _my_office(c.id); j jurisdictions; d decrees; last int; s text; v numeric;
begin
  select * into j from jurisdictions where key = k;
  select * into d from decrees where id = p_decree;
  if not found or d.office <> j.type then perform _fail('Your office cannot issue that order.'); end if;
  select max(day) into last from decree_log where key = k and decree_id = p_decree;
  if last is not null and game_day() - last < d.cooldown_days then
    perform _fail(format('You can issue this again on Day %s.', last + d.cooldown_days));
  end if;
  if d.treasury_delta < 0 and j.treasury < -d.treasury_delta then perform _fail('The treasury cannot fund this.'); end if;
  perform _use_energy(c.id, 1);
  for s, v in select key, value::numeric from jsonb_each_text(d.effects) loop
    if s = 'mood' then
      update jurisdictions set mood = mood + v where key = k;
    else
      execute format('update jurisdictions set %1$I = least(100, greatest(0, %1$I + $1)) where key = $2', s) using v, k;
    end if;
  end loop;
  update jurisdictions set treasury = treasury + d.treasury_delta where key = k;
  insert into decree_log (key, decree_id, citizen_id, day) values (k, p_decree, c.id, game_day());
  perform _news((select title from office_rules where type = j.type) || ' ' || c.display_name || ' ('
                || _place(k) || '): ' || d.label || '.');
end $$;

-- LG Chairmen, Governors and the President can order arrests within their jurisdiction.
-- One arrest per leader per day; nobody can be re-arrested within 3 days; you cannot arrest
-- someone holding an office of equal or higher rank. Arresting a clean citizen backfires.
create or replace function order_arrest(p_target uuid, p_charge text) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); k text := _my_office(c.id); j jurisdictions; t citizens; t_office text; wrongful boolean;
begin
  select * into j from jurisdictions where key = k;
  if j.type = 'SEN' then perform _fail('Senators make laws. Only executives can order arrests.'); end if;
  if p_charge not in ('Inciting violence','Vote buying','Fraud','Cybercrime','Thuggery','Defamation','Breach of public peace') then
    perform _fail('Choose a charge from the list.');
  end if;
  select * into t from citizens where id = p_target for update;
  if not found or t.banned then perform _fail('That citizen was not found.'); end if;
  if t.id = c.id then perform _fail('You cannot arrest yourself.'); end if;
  if (j.type = 'LG' and t.lga_id <> j.lga_id) or (j.type = 'GOV' and t.state_id <> j.state_id) then
    perform _fail('That citizen lives outside your jurisdiction.');
  end if;
  select o.key into t_office from offices o where o.holder_id = t.id;
  if t_office is not null and _rank((select type from jurisdictions where key = t_office)) >= _rank(j.type) then
    perform _fail('You cannot arrest someone of equal or higher office.');
  end if;
  if t.detained_until > now() then perform _fail('That citizen is already in custody.'); end if;
  if t.last_arrested_at > now() - interval '3 days' then perform _fail('That citizen was arrested recently. The courts will not allow it.'); end if;
  if exists (select 1 from arrests where by_id = c.id and day = game_day()) then
    perform _fail('You can only order one arrest a day.');
  end if;
  perform _use_energy(c.id, 2);
  wrongful := t.scandal < 20;
  update citizens set detained_until = now() + interval '24 hours', detained_by = c.id, detained_charge = p_charge,
                      last_arrested_at = now() where id = t.id;
  insert into arrests (by_id, by_office, target_id, charge, day) values (c.id, k, t.id, p_charge, game_day());
  -- A candidate in custody: sympathy if innocent, damage if not.
  update candidates set popularity = least(100, greatest(0, popularity + case when wrongful then 5 else -10 end))
   where citizen_id = t.id and votes is null;
  if wrongful then
    update citizens set scandal = scandal + 15, integrity = greatest(0, integrity - 10) where id = c.id;
    update jurisdictions set mood = mood - 5 where key = k;
    perform _news('Outrage as ' || t.display_name || ' is detained on the orders of ' || c.display_name
                  || ' over "' || p_charge || '". #Free' || replace(t.display_name, ' ', '') || ' trends.');
  else
    update citizens set rep = rep + 1 where id = c.id;
    update jurisdictions set mood = mood + 3 where key = k;
    perform _news(t.display_name || ' arrested for ' || lower(p_charge) || ' on the orders of ' || c.display_name || '.');
  end if;
end $$;

-- Bail is the one action allowed in custody.
create or replace function post_bail() returns void
language plpgsql security definer set search_path = public as $$
declare c citizens; fee bigint;
begin
  select * into c from citizens where id = auth.uid() for update;
  if not found then perform _fail('Register as a citizen first.'); end if;
  if c.detained_until is null or c.detained_until <= now() then perform _fail('You are not in custody.'); end if;
  fee := 3000 + (select coalesce(max(_rank(j.type)), 1) * 1000 from offices o join jurisdictions j on j.key = o.key where o.holder_id = c.detained_by);
  perform _move(c.id, 'coins', -fee, 'bail', c.detained_charge);
  update citizens set detained_until = null where id = c.id;
  update arrests set released_at = now(), released_how = 'bail'
   where id = (select max(id) from arrests where target_id = c.id and released_at is null);
  perform _news(c.display_name || ' is released on bail.');
end $$;

-- ---------- Owner tools ----------
create or replace function admin_ip_report() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  return jsonb_build_object(
    'shared', (select coalesce(jsonb_agg(x), '[]') from (
        select ip, count(*) as accounts, jsonb_agg(jsonb_build_object('id', id, 'name', display_name)) as players,
               exists (select 1 from ip_allowlist a where a.ip = s.ip) as allowed
          from (select id, display_name, coalesce(last_ip, signup_ip) as ip from citizens) s
         where ip is not null group by ip having count(*) > 1 order by count(*) desc limit 100) x),
    'allowlist', (select coalesce(jsonb_agg(a order by a.added_at desc), '[]') from ip_allowlist a),
    'detained', (select coalesce(jsonb_agg(x), '[]') from (
        select c.id, c.display_name as name, c.detained_charge as charge, c.detained_until, b.display_name as by
          from citizens c left join citizens b on b.id = c.detained_by where c.detained_until > now()) x),
    'arrests_today', (select count(*) from arrests where day = game_day()),
    'decrees_today', (select count(*) from decree_log where day = game_day()));
end $$;

create or replace function admin_allow_ip(p_ip text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  insert into ip_allowlist (ip, note) values (trim(p_ip), p_note) on conflict (ip) do update set note = excluded.note;
end $$;

create or replace function admin_release(p_target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  update citizens set detained_until = null where id = p_target;
  update arrests set released_at = now(), released_how = 'owner'
   where target_id = p_target and released_at is null;
end $$;

create or replace function admin_players(p_search text default '', p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
begin
  perform _admin_only();
  return (select coalesce(jsonb_agg(x), '[]') from (
    select c.id, c.display_name as name, u.email, s.name as state, g.name as lga, c.created_at, c.last_seen,
           w.coins, w.stash, w.cp, floor(c.rep) as rep, c.streak, c.banned, c.suspended_until, c.muted_until,
           c.detained_until, c.scandal, c.signup_ip, c.last_ip, c.vin, p.abbr as party, o.key as office
      from citizens c
      join auth.users u on u.id = c.id
      join wallets w on w.citizen_id = c.id
      join states s on s.id = c.state_id
      join lgas g on g.id = c.lga_id
      left join party_members m on m.citizen_id = c.id
      left join parties p on p.id = m.party_id
      left join offices o on o.holder_id = c.id
     where p_search = '' or c.display_name ilike '%' || p_search || '%' or u.email ilike '%' || p_search || '%'
        or c.last_ip = p_search or c.signup_ip = p_search or c.vin ilike p_search || '%'
     order by c.created_at desc limit least(p_limit, 500)) x);
end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function
  game_day(), is_admin(), register_citizen(text, text), touch(), claim_daily(), start_ad(), finish_ad(),
  do_hustle(text), get_trivia(), answer_trivia(int), claim_tasks(), cast_vote(uuid, uuid), post_gist(text, text),
  leaderboard(), stash_coins(bigint), unstash_coins(bigint), gift_coins(uuid, bigint), redeem_cp(bigint, text),
  buy_item(text), join_party(uuid), create_party(text, text, text), leave_party(), declare_candidacy(text),
  campaign(text), withdraw_candidacy(), start_project(text), town_hall(), pay_salaries(),
  revalidate_card(uuid), make_decree(text), order_arrest(uuid, text), post_bail(),
  admin_dashboard(), admin_players(text, int), admin_player(uuid), admin_sanction(uuid, text, text, int, bigint),
  admin_sanctions_log(int), admin_redemptions(), admin_resolve_redemption(bigint, boolean), admin_posts(int),
  admin_delete_post(bigint), admin_set_playtest(boolean), admin_broadcast(text),
  admin_ip_report(), admin_allow_ip(text, text), admin_release(uuid)
to authenticated;
