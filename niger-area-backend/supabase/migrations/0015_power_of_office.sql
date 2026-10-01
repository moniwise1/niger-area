-- Niger Area: leaders set prices and processes; office history and term limits.
--   * President: national VAT on all purchases (to the federal treasury), nomination fee multiplier for
--     Senate/Governor/President races, and presidential tenure (90 to 150 days, i.e. 3 to 5 "years").
--   * Governor: state tax on residents' purchases (to the state treasury) and the LG nomination fee multiplier.
--   * Every term served is recorded, so profiles show "Ex-President · 2 terms".
--   * Nobody can win the presidency more than 10 times.

create table policies (
  id text primary key,                 -- 'nation' or a state id
  vat numeric not null default 0,      -- nation only
  state_tax numeric not null default 0,-- states only
  fee_mult numeric not null default 1,
  updated_day int,
  updated_by uuid references citizens
);
insert into policies (id, vat, fee_mult) values ('nation', 0.075, 1);
insert into policies (id) select id from states where has_governor;
alter table policies enable row level security;
create policy read_all on policies for select to authenticated using (true);

create table office_terms (
  id bigserial primary key,
  citizen_id uuid not null references citizens on delete cascade,
  key text not null references jurisdictions,
  start_day int not null,
  end_day int,
  ended_how text
);
create index office_terms_citizen_idx on office_terms (citizen_id);
alter table office_terms enable row level security;
create policy read_all on office_terms for select to authenticated using (true);

-- Seed history for anyone already in office.
insert into office_terms (citizen_id, key, start_day)
  select holder_id, key, greatest(1, term_ends_day - (select r.term_days from office_rules r join jurisdictions j on j.type = r.type where j.key = offices.key))
    from offices where holder_id is not null;

-- When a holder leaves a seat for any reason, close their open term. The reason comes from na.end_how.
create or replace function _close_term() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.holder_id is not null and old.holder_id is distinct from new.holder_id then
    update office_terms set end_day = game_day(), ended_how = coalesce(nullif(current_setting('na.end_how', true), ''), 'left office')
     where citizen_id = old.holder_id and key = old.key and end_day is null;
  end if;
  return new;
end $$;
create trigger offices_close_term after update on offices for each row execute function _close_term();

create or replace function _tenure_years(p_days int) returns text
language sql immutable as $$ select round(p_days / 30.0)::int || '-year' $$;

-- ---------- Prices ----------
create or replace function buy_item(p_item text) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); it shop_items; have int; vat numeric; stax numeric; v bigint; s bigint;
begin
  if p_item = 'spouse' then perform _fail('Marriage is between citizens. Open someone''s profile and propose.'); end if;
  select * into it from shop_items where id = p_item;
  if not found then perform _fail('That item is not for sale.'); end if;
  select qty into have from citizen_items where citizen_id = c.id and item_id = p_item;
  have := coalesce(have, 0);
  if have >= it.max_qty then perform _fail('You already have the maximum of this.'); end if;
  if it.requires is not null and not exists (select 1 from citizen_items where citizen_id = c.id and item_id = it.requires) then
    perform _fail(case when it.requires = 'spouse' then 'Get married first.' else 'Buy the previous upgrade first.' end);
  end if;
  select p.vat into vat from policies p where id = 'nation';
  select p.state_tax into stax from policies p where id = c.state_id;
  v := round(it.cost * coalesce(vat, 0)); s := round(it.cost * coalesce(stax, 0));
  perform _move(c.id, 'coins', -(it.cost + v + s), 'purchase_item', p_item);
  if v > 0 then update jurisdictions set treasury = treasury + v where key = 'PRES'; end if;
  if s > 0 then update jurisdictions set treasury = treasury + s where key = 'GOV:' || c.state_id; end if;
  insert into citizen_items (citizen_id, item_id, qty) values (c.id, p_item, 1)
  on conflict (citizen_id, item_id) do update set qty = citizen_items.qty + 1;
  if it.kind = 'house' then perform _award(c.id, 'homeowner'); end if;
  if p_item = 'house5' then perform _award(c.id, 'mansion'); end if;
  if it.kind = 'business' then perform _award(c.id, 'entrepreneur'); end if;
  if p_item = 'station' then perform _award(c.id, 'oil_baron'); end if;
end $$;

create or replace function _nomination_fee(p_key text) returns bigint
language sql stable security definer set search_path = public as $$
  select round(r.fee * coalesce((select fee_mult from policies where id = case when j.type = 'LG' then j.state_id else 'nation' end), 1))::bigint
    from jurisdictions j join office_rules r on r.type = j.type where j.key = p_key
$$;

create or replace function set_national_policy(p_vat numeric, p_fee_mult numeric) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); k text := _my_office(c.id); old policies;
begin
  if k <> 'PRES' then perform _fail('Only the President sets national policy.'); end if;
  if p_vat < 0 or p_vat > 0.25 then perform _fail('VAT must be between 0% and 25%.'); end if;
  if p_fee_mult < 0.5 or p_fee_mult > 2 then perform _fail('Nomination fees can be set from half to double.'); end if;
  select * into old from policies where id = 'nation';
  if old.updated_day is not null and game_day() - old.updated_day < 3 then
    perform _fail(format('You can change national policy again on Day %s.', old.updated_day + 3));
  end if;
  update policies set vat = p_vat, fee_mult = p_fee_mult, updated_day = game_day(), updated_by = c.id where id = 'nation';
  -- Raising VAT angers people; cutting it pleases them.
  update jurisdictions set mood = mood - round((p_vat - old.vat) * 100) where key = 'PRES';
  perform _news('President ' || c.display_name || ' sets VAT at ' || round(p_vat * 100, 1) || '% and nomination fees at '
                || round(p_fee_mult * 100) || '% of the standard rate.');
end $$;

create or replace function set_state_policy(p_tax numeric, p_fee_mult numeric) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); k text := _my_office(c.id); sid text; old policies;
begin
  if k not like 'GOV:%' then perform _fail('Only a Governor sets state policy.'); end if;
  sid := split_part(k, ':', 2);
  if p_tax < 0 or p_tax > 0.15 then perform _fail('State tax must be between 0% and 15%.'); end if;
  if p_fee_mult < 0.5 or p_fee_mult > 2 then perform _fail('LG nomination fees can be set from half to double.'); end if;
  select * into old from policies where id = sid;
  if old.updated_day is not null and game_day() - old.updated_day < 3 then
    perform _fail(format('You can change state policy again on Day %s.', old.updated_day + 3));
  end if;
  update policies set state_tax = p_tax, fee_mult = p_fee_mult, updated_day = game_day(), updated_by = c.id where id = sid;
  update jurisdictions set mood = mood - round((p_tax - old.state_tax) * 100) where key = k;
  perform _news('Governor ' || c.display_name || ' sets ' || (select name from states where id = sid) || ' state tax at '
                || round(p_tax * 100, 1) || '% and LG nomination fees at ' || round(p_fee_mult * 100) || '%.');
end $$;

-- 90 to 150 days. Applies to future terms, and to the current one (never ending it sooner than 3 days from now).
create or replace function set_presidential_tenure(p_days int) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); k text := _my_office(c.id); start_day int; old_days int; new_end int;
begin
  if k <> 'PRES' then perform _fail('Only the President can change the presidential tenure.'); end if;
  if p_days < 90 or p_days > 150 then perform _fail('Presidential tenure must be between 90 and 150 days (3 to 5 years).'); end if;
  select term_days into old_days from office_rules where type = 'PRES';
  if p_days = old_days then perform _fail('That is already the tenure.'); end if;
  select t.start_day into start_day from office_terms t where t.citizen_id = c.id and t.key = 'PRES' and t.end_day is null;
  update office_rules set term_days = p_days where type = 'PRES';
  new_end := greatest(game_day() + 3, coalesce(start_day, game_day()) + p_days);
  update offices set term_ends_day = new_end where key = 'PRES';
  update elections set poll_day = new_end where key = 'PRES' and status = 'open';
  if p_days > old_days then update jurisdictions set mood = mood - 8 where key = 'PRES'; end if;
  perform _news('President ' || c.display_name || ' ' || case when p_days > old_days then 'extends' else 'shortens' end
                || ' the presidential tenure to ' || _tenure_years(p_days) || ' (' || p_days || ' days). Next presidential election: Day ' || new_end || '.');
end $$;

-- ---------- Elections: fees, term limit, history ----------
create or replace function declare_candidacy(p_key text) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); j jurisdictions; ru office_rules; e elections; m party_members; pop numeric; fee bigint;
begin
  select * into j from jurisdictions where key = p_key;
  if not found then perform _fail('That office does not exist.'); end if;
  if (j.type = 'LG' and j.lga_id <> c.lga_id) or (j.type in ('SEN', 'GOV') and j.state_id <> c.state_id) then
    perform _fail('You can only run where you are registered to vote.');
  end if;
  if c.kyc_level < 1 then perform _fail('Verify your phone number to run for office.'); end if;
  if j.type = 'PRES' and (select count(*) from office_terms where citizen_id = c.id and key = 'PRES') >= 10 then
    perform _fail('You have won the presidency 10 times. The constitution says no more.');
  end if;
  select * into m from party_members where citizen_id = c.id;
  if not found then perform _fail('You need a party ticket first.'); end if;
  select * into ru from office_rules where type = j.type;
  if c.rep < ru.min_rep then perform _fail(format('You need reputation %s to run for %s.', ru.min_rep, ru.title)); end if;
  select * into e from elections where key = p_key and status = 'open';
  if not found or e.poll_day <= game_day() then perform _fail('Nominations for this race are closed.'); end if;
  perform _require_card(c.id, e.id);
  fee := _nomination_fee(p_key);
  pop := 8 + _status(c.id) * 0.6 + least(c.rep, 60) * 0.4
       + case when exists (select 1 from offices where key = p_key and holder_id = c.id) then _approval(p_key) * 0.4 else 0 end;
  perform _move(c.id, 'stash', -fee, 'nomination_fee', p_key);
  begin
    insert into candidates (election_id, citizen_id, party_id, popularity) values (e.id, c.id, m.party_id, pop);
  exception when unique_violation then
    perform _fail('Either your party already has a candidate in this race, or you are running elsewhere.');
  end;
  perform _award(c.id, 'candidate');
  perform _news(c.display_name || ' picks the ' || (select abbr from parties where id = m.party_id)
                || ' ticket for ' || _place(p_key) || '.');
end $$;

create or replace function _resolve_election(p_election uuid, p_day int) returns void
language plpgsql security definer set search_path = public as $$
declare e elections; j jurisdictions; ru office_rules; n int; v_turnout bigint; win candidates; runner candidates; wname text; sname text; held uuid;
begin
  select * into e from elections where id = p_election for update;
  select * into j from jurisdictions where key = e.key;
  select * into ru from office_rules where type = j.type;
  select count(*) into n from candidates where election_id = e.id;
  select holder_id into held from offices where key = e.key;

  if n = 0 then
    perform set_config('na.end_how', 'term ended', true);
    update elections set status = 'closed', turnout = 0 where id = e.id;
    update offices set holder_id = null, holder_party = null, term_ends_day = p_day + 14 where key = e.key;
    insert into elections (key, poll_day) values (e.key, p_day + 14);
    insert into news (day, body, kind) values (p_day, 'No candidate filed for ' || _place(e.key)
      || '. A caretaker committee takes over until fresh polls in 14 days.', 'election');
    return;
  end if;

  v_turnout := floor((ru.voters_min + random() * (ru.voters_max - ru.voters_min)) * (0.28 + random() * 0.14));

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
  select * into runner from candidates where election_id = e.id and citizen_id <> win.citizen_id order by votes desc limit 1;
  select display_name into wname from citizens where id = win.citizen_id;
  select display_name into sname from citizens where id = runner.citizen_id;

  update elections set status = 'closed', turnout = v_turnout where id = e.id;
  -- Winning a new seat vacates any other seat the winner held.
  perform set_config('na.end_how', 'moved to a new office', true);
  update offices set holder_id = null, holder_party = null where holder_id = win.citizen_id and key <> e.key;
  perform set_config('na.end_how', 'voted out', true);
  if held = win.citizen_id then
    update office_terms set end_day = p_day, ended_how = 're-elected' where citizen_id = held and key = e.key and end_day is null;
  end if;
  update offices set holder_id = win.citizen_id, holder_party = win.party_id, term_ends_day = p_day + ru.term_days
   where key = e.key;
  insert into office_terms (citizen_id, key, start_day) values (win.citizen_id, e.key, p_day);
  update jurisdictions set mood = 10, last_salary_day = p_day where key = e.key;
  update citizens set offices_held = offices_held + 1, rep = rep + 8 where id = win.citizen_id;
  perform _move(win.citizen_id, 'cp', 500, 'election_win', e.key, 'win:' || e.id);
  perform _award(win.citizen_id, case j.type when 'LG' then 'won_lg' when 'SEN' then 'won_sen' when 'GOV' then 'won_gov' else 'won_pres' end);
  insert into elections (key, poll_day) values (e.key, p_day + ru.term_days);
  insert into news (day, body, kind) values (p_day, 'INEC declares ' || wname || ' ('
    || (select abbr from parties where id = win.party_id) || ') winner: ' || _place(e.key)
    || ', with ' || to_char(win.votes, 'FM999,999,999') || ' votes'
    || case when runner.citizen_id is not null
            then '. ' || sname || ' (' || (select abbr from parties where id = runner.party_id) || ') came second with '
                 || to_char(runner.votes, 'FM999,999,999') || '.'
            else ', unopposed.' end
    || case when held is not null and held <> win.citizen_id then ' The incumbent is voted out.'
            when held = win.citizen_id then ' The incumbent is re-elected.' else '' end, 'election');
end $$;

create or replace function _efcc_raid(p_citizen uuid, p_day int) returns void
language plpgsql security definer set search_path = public as $$
declare w wallets; seized_c bigint; seized_s bigint; name text;
begin
  select * into w from wallets where citizen_id = p_citizen for update;
  seized_c := floor(w.coins * 0.3);
  seized_s := floor(w.stash * 0.5);
  perform _move(p_citizen, 'coins', -seized_c, 'efcc_seizure', null, 'efcc:c:' || p_citizen || ':' || p_day);
  perform _move(p_citizen, 'stash', -seized_s, 'efcc_seizure', null, 'efcc:s:' || p_citizen || ':' || p_day);
  perform set_config('na.end_how', 'removed after an EFCC raid', true);
  update offices set holder_id = null, holder_party = null where holder_id = p_citizen;
  delete from candidates where citizen_id = p_citizen and votes is null;
  update citizens set scandal = 15, integrity = greatest(0, integrity - 10), rep = rep * 0.5 where id = p_citizen;
  select display_name into name from citizens where id = p_citizen;
  insert into news (day, body, kind) values (p_day, 'EFCC operatives raid the home of ' || name || '.', 'law');
end $$;

create or replace function admin_sanction(p_target uuid, p_kind text, p_reason text, p_days int default null, p_amount bigint default null)
returns void
language plpgsql security definer set search_path = public as $$
declare n text; until_at timestamptz := case when p_days is not null then now() + make_interval(days => p_days) end; headline text;
begin
  perform _admin_only();
  select display_name into n from citizens where id = p_target;
  if n is null then perform _fail('Player not found.'); end if;
  if coalesce(trim(p_reason), '') = '' then perform _fail('Give a reason. The player will see it.'); end if;
  perform set_config('na.end_how', 'removed by the authorities', true);
  case p_kind
    when 'warn' then headline := n || ' is warned by the authorities: ' || p_reason;
    when 'mute' then
      update citizens set muted_until = coalesce(until_at, now() + interval '1 day') where id = p_target;
      headline := n || ' is muted on Gist for ' || coalesce(p_days, 1) || ' day(s): ' || p_reason;
    when 'unmute' then update citizens set muted_until = null where id = p_target;
    when 'suspend' then
      update citizens set suspended_until = coalesce(until_at, now() + interval '3 days') where id = p_target;
      headline := n || ' is suspended for ' || coalesce(p_days, 3) || ' day(s): ' || p_reason;
    when 'unsuspend' then
      update citizens set suspended_until = null where id = p_target;
      headline := n || ' is reinstated after a suspension.';
    when 'ban' then
      update citizens set banned = true, ban_reason = p_reason where id = p_target;
      update offices set holder_id = null, holder_party = null where holder_id = p_target;
      delete from candidates where citizen_id = p_target and votes is null;
      headline := n || ' is banned from Niger Area: ' || p_reason;
    when 'unban' then
      update citizens set banned = false, ban_reason = null where id = p_target;
      headline := n || ' is reinstated as a citizen.';
    when 'fine' then
      if coalesce(p_amount, 0) <= 0 then perform _fail('Enter the fine amount.'); end if;
      perform _move(p_target, 'coins', -least(p_amount, (select coins from wallets where citizen_id = p_target)), 'admin_fine', p_reason);
      headline := n || ' is fined ' || to_char(p_amount, 'FM999,999,999') || ' coins: ' || p_reason;
    when 'grant' then
      if coalesce(p_amount, 0) <= 0 then perform _fail('Enter the amount to grant.'); end if;
      perform _move(p_target, 'coins', p_amount, 'admin_grant', p_reason);
    when 'reset_rep' then
      update citizens set rep = 0 where id = p_target;
      headline := n || '''s reputation is wiped by the authorities: ' || p_reason;
    when 'remove_office' then
      update offices set holder_id = null, holder_party = null where holder_id = p_target;
      headline := n || ' is removed from office: ' || p_reason;
    when 'disqualify' then
      delete from candidates where citizen_id = p_target and votes is null;
      headline := n || ' is disqualified from the ballot: ' || p_reason;
    else perform _fail('Unknown sanction.');
  end case;
  insert into sanctions (citizen_id, admin_id, kind, reason, amount, until)
  values (p_target, auth.uid(), p_kind, p_reason, p_amount, until_at);
  if headline is not null then insert into news (day, body, kind) values (game_day(), headline, 'law'); end if;
end $$;

-- ---------- Salaries: set by the President, paid from each government's treasury ----------
alter table office_rules add column salary_set_day int;

create or replace function set_salary(p_type office_type, p_amount bigint) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); k text := _my_office(c.id); old office_rules; cap bigint;
begin
  if k <> 'PRES' then perform _fail('Only the President sets salaries for office holders.'); end if;
  cap := case when p_type = 'PRES' then 10000 else 5000 end;
  if p_amount < 0 or p_amount > cap then perform _fail(format('That salary must be between 0 and %s coins a day.', cap)); end if;
  select * into old from office_rules where type = p_type;
  if old.salary_set_day is not null and game_day() - old.salary_set_day < 3 then
    perform _fail(format('You can change this salary again on Day %s.', old.salary_set_day + 3));
  end if;
  update office_rules set salary = p_amount, salary_set_day = game_day() where type = p_type;
  -- A President who raises their own pay faces the public.
  if p_type = 'PRES' and p_amount > old.salary then
    update jurisdictions set mood = mood - least(20, round((p_amount - old.salary) / 500.0)) where key = 'PRES';
  end if;
  perform _news('President ' || c.display_name || ' sets the daily salary of ' ||
                case p_type when 'PRES' then 'the President' when 'GOV' then 'Governors' when 'SEN' then 'Senators' else 'LG Chairmen' end
                || ' at ' || to_char(p_amount, 'FM999,999') || ' coins (was ' || to_char(old.salary, 'FM999,999') || ').');
end $$;

create or replace function advance_day() returns int
language plpgsql security definer set search_path = public as $$
declare d int; r record; paid bigint;
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

  -- Salaries come out of the treasury of the office's own government. An empty treasury pays what it can.
  for r in select o.key, o.holder_id, ru.salary, j.treasury
             from offices o join jurisdictions j on j.key = o.key join office_rules ru on ru.type = j.type
            where o.holder_id is not null loop
    paid := least(r.salary, greatest(r.treasury, 0));
    if paid > 0 then
      update jurisdictions set treasury = treasury - paid where key = r.key;
      perform _move(r.holder_id, 'coins', paid, 'salary', r.key, 'salary:' || r.key || ':' || d);
    end if;
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

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function
  game_day(), is_admin(), register_citizen(text, text), touch(), claim_daily(), start_ad(), finish_ad(),
  do_hustle(text), get_trivia(), answer_trivia(int), claim_tasks(), cast_vote(uuid, uuid), post_gist(text, text),
  leaderboard(), stash_coins(bigint), unstash_coins(bigint), gift_coins(uuid, bigint), redeem_cp(bigint, text),
  buy_item(text), join_party(uuid), create_party(text, text, text), leave_party(), declare_candidacy(text),
  campaign(text), withdraw_candidacy(), start_project(text), town_hall(), pay_salaries(),
  revalidate_card(uuid), make_decree(text), order_arrest(uuid, text), post_bail(),
  update_profile(text, text), set_avatar(text), request_connection(uuid), respond_connection(uuid, boolean),
  remove_connection(uuid), send_message(uuid, text), mark_read(uuid), my_conversations(), report_citizen(uuid, text),
  propose(uuid, text), withdraw_proposal(), answer_proposal(uuid, boolean), divorce(), set_show_spouse(boolean),
  public_spouse(uuid), post_campaign(text), toggle_like(bigint),
  set_national_policy(numeric, numeric), set_state_policy(numeric, numeric), set_presidential_tenure(int), set_salary(office_type, bigint),
  admin_dashboard(), admin_players(text, int), admin_player(uuid), admin_sanction(uuid, text, text, int, bigint),
  admin_sanctions_log(int), admin_redemptions(), admin_resolve_redemption(bigint, boolean), admin_posts(int),
  admin_delete_post(bigint), admin_set_playtest(boolean), admin_broadcast(text),
  admin_ip_report(), admin_allow_ip(text, text), admin_release(uuid),
  admin_reports(), admin_close_report(bigint), admin_report_messages(bigint)
to authenticated;
