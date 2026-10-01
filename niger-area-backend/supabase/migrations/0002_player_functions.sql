-- Niger Area: everything a player can do, as server-side functions.
-- Clients call these with supabase.rpc(...). Each one checks the rules, then moves coins
-- through _move(), which writes the ledger. Errors use SQLSTATE P0001 with a player-facing message.

-- ---------- Internal helpers ----------

create or replace function game_day() returns int
language sql stable set search_path = public as $$
  select day from game_clock where id = 1
$$;

create or replace function _fail(msg text) returns void
language plpgsql set search_path = public as $$
begin
  raise exception '%', msg using errcode = 'P0001';
end $$;

-- The calling citizen, row-locked for the rest of the transaction.
create or replace function _me() returns citizens
language plpgsql security definer set search_path = public as $$
declare c citizens;
begin
  if auth.uid() is null then perform _fail('Sign in first.'); end if;
  select * into c from citizens where id = auth.uid() for update;
  if not found then perform _fail('Register as a citizen first.'); end if;
  if c.banned then perform _fail('This account is suspended.'); end if;
  return c;
end $$;

-- The only function that changes a balance.
create or replace function _move(p_citizen uuid, p_cur currency, p_delta bigint, p_reason text,
                                 p_ref text default null, p_idem text default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare bal bigint;
begin
  if p_delta = 0 then return null; end if;
  begin
    if p_cur = 'coins' then
      update wallets set coins = coins + p_delta where citizen_id = p_citizen returning coins into bal;
    elsif p_cur = 'stash' then
      update wallets set stash = stash + p_delta where citizen_id = p_citizen returning stash into bal;
    else
      update wallets set cp = cp + p_delta where citizen_id = p_citizen returning cp into bal;
    end if;
  exception when check_violation then
    perform _fail(case p_cur when 'coins' then 'Not enough coins in your wallet.'
                             when 'stash' then 'Not enough coins in your campaign stash.'
                             else 'Not enough civic points.' end);
  end;
  if bal is null then perform _fail('Wallet not found.'); end if;
  insert into ledger (citizen_id, cur, delta, balance_after, reason, ref, idempotency_key)
  values (p_citizen, p_cur, p_delta, bal, p_reason, p_ref, p_idem);
  return bal;
end $$;

create or replace function _limits(p_citizen uuid) returns daily_limits
language plpgsql security definer set search_path = public as $$
declare l daily_limits;
begin
  insert into daily_limits (citizen_id, day) values (p_citizen, game_day()) on conflict do nothing;
  select * into l from daily_limits where citizen_id = p_citizen and day = game_day() for update;
  return l;
end $$;

create or replace function _use_energy(p_citizen uuid, p_n int) returns void
language plpgsql security definer set search_path = public as $$
begin
  update citizens set energy = 6, energy_day = game_day()
   where id = p_citizen and energy_day < game_day();
  update citizens set energy = energy - p_n where id = p_citizen and energy >= p_n;
  if not found then perform _fail('No energy left today. Come back tomorrow.'); end if;
end $$;

-- Bought status (household, gifts, party chair), capped at 20. Reputation is separate and uncapped.
create or replace function _status(p_citizen uuid) returns int
language sql stable security definer set search_path = public as $$
  select least(20, floor(
      coalesce((select sum(ci.qty * s.status_points) from citizen_items ci
                 join shop_items s on s.id = ci.item_id where ci.citizen_id = p_citizen), 0)
    + (select gift_status from citizens where id = p_citizen)
    + (select case when exists (select 1 from party_members where citizen_id = p_citizen and role = 'chair')
                   then 5 else 0 end)))::int
$$;

create or replace function _party_strength(p_party uuid) returns numeric
language sql stable security definer set search_path = public as $$
  with t as (
    select p.id, p.base_members + (select count(*) from party_members m where m.party_id = p.id) as n
      from parties p)
  select coalesce(100.0 * (select n from t where id = p_party) / nullif((select sum(n) from t), 0), 0)
$$;

create or replace function _approval(p_key text) returns numeric
language sql stable security definer set search_path = public as $$
  select greatest(0, least(100, (roads + power + health + edu + security + economy) / 6 + mood))
    from jurisdictions where key = p_key
$$;

create or replace function _place(p_key text) returns text
language sql stable security definer set search_path = public as $$
  select case j.type
           when 'PRES' then 'President of Niger Area'
           when 'GOV'  then 'Governor, ' || s.name || ' State'
           when 'SEN'  then 'Senator, ' || s.name || ' District'
           else 'LG Chairman, ' || l.name || ' LGA' end
    from jurisdictions j
    left join states s on s.id = j.state_id
    left join lgas   l on l.id = j.lga_id
   where j.key = p_key
$$;

create or replace function _news(p_body text) returns void
language sql security definer set search_path = public as $$
  insert into news (day, body) values (game_day(), p_body)
$$;

-- ---------- Citizenship ----------

create or replace function register_citizen(p_name text, p_lga text) returns void
language plpgsql security definer set search_path = public as $$
declare s text;
begin
  if auth.uid() is null then perform _fail('Sign in first.'); end if;
  if exists (select 1 from citizens where id = auth.uid()) then perform _fail('You are already a citizen.'); end if;
  select state_id into s from lgas where id = p_lga;
  if s is null then perform _fail('Unknown local government.'); end if;
  insert into citizens (id, display_name, state_id, lga_id, energy_day)
  values (auth.uid(), trim(p_name), s, p_lga, game_day());
  insert into wallets (citizen_id, coins) values (auth.uid(), 0);
  perform _move(auth.uid(), 'coins', 1500, 'welcome_bonus', null, 'welcome:' || auth.uid());
  perform _news(trim(p_name) || ' registers as a citizen of Niger Area.');
end $$;

-- ---------- Wallet ----------

-- 1,000 coins a day. Civic points only for phone-verified accounts, so throwaway accounts earn nothing redeemable.
create or replace function claim_daily() returns bigint
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); l daily_limits := _limits(c.id); bal bigint;
begin
  if l.claimed then perform _fail('You already claimed today''s coins.'); end if;
  update daily_limits set claimed = true where citizen_id = c.id and day = l.day;
  bal := _move(c.id, 'coins', 1000, 'daily_bonus', null, 'daily:' || c.id || ':' || l.day);
  if c.kyc_level >= 1 then
    perform _move(c.id, 'cp', 20, 'daily_checkin', null, 'dailycp:' || c.id || ':' || l.day);
  end if;
  return bal;
end $$;

-- Called only by the ad-reward edge function, after Google's signature check. 5 ads x 200 = 1,000 a day.
create or replace function credit_ad_reward(p_citizen uuid, p_txn text) returns boolean
language plpgsql security definer set search_path = public as $$
declare l daily_limits;
begin
  insert into ad_rewards (transaction_id, citizen_id, coins) values (p_txn, p_citizen, 200)
  on conflict do nothing;
  if not found then return false; end if;                 -- replayed callback
  l := _limits(p_citizen);
  if l.ads >= 5 then return false; end if;
  update daily_limits set ads = ads + 1 where citizen_id = p_citizen and day = l.day;
  perform _move(p_citizen, 'coins', 200, 'rewarded_ad', p_txn, 'ad:' || p_txn);
  return true;
end $$;

create or replace function stash_coins(p_amount bigint) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me();
begin
  if p_amount <= 0 then perform _fail('Enter an amount above zero.'); end if;
  perform _move(c.id, 'coins', -p_amount, 'to_stash');
  perform _move(c.id, 'stash',  p_amount, 'to_stash');
end $$;

-- Withdrawing from the stash burns a 10% levy, so the stash isn't a free parking spot.
create or replace function unstash_coins(p_amount bigint) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me();
begin
  if p_amount <= 0 then perform _fail('Enter an amount above zero.'); end if;
  perform _move(c.id, 'stash', -p_amount, 'from_stash');
  perform _move(c.id, 'coins', floor(p_amount * 0.9)::bigint, 'from_stash', 'levy 10%');
end $$;

-- Gifts: max 2,000 sent and 5,000 received per day, both accounts phone-verified and 7+ days old.
-- These limits are what stop coin farming rings and off-platform coin sales.
create or replace function gift_coins(p_to uuid, p_amount bigint) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); r citizens; l daily_limits; received bigint;
begin
  if p_amount <= 0 then perform _fail('Enter an amount above zero.'); end if;
  if p_to = c.id then perform _fail('You cannot send coins to yourself.'); end if;
  select * into r from citizens where id = p_to;
  if not found or r.banned then perform _fail('That citizen was not found.'); end if;
  if c.kyc_level < 1 or r.kyc_level < 1 then perform _fail('Both of you need a verified phone number to send coins.'); end if;
  if c.created_at > now() - interval '7 days' or r.created_at > now() - interval '7 days' then
    perform _fail('Accounts must be at least 7 days old to send or receive coins.');
  end if;
  l := _limits(c.id);
  if l.gifted + p_amount > 2000 then
    perform _fail(format('You can send %s more coins today.', 2000 - l.gifted));
  end if;
  select coalesce(sum(delta), 0) into received from ledger
   where citizen_id = p_to and reason = 'gift_in' and ref = game_day()::text;
  if received + p_amount > 5000 then perform _fail('That citizen has reached today''s limit for receiving gifts.'); end if;
  update daily_limits set gifted = gifted + p_amount where citizen_id = c.id and day = l.day;
  perform _move(c.id, 'coins', -p_amount, 'gift_out', p_to::text);
  perform _move(p_to,  'coins',  p_amount, 'gift_in',  game_day()::text);
  update citizens set gift_status = gift_status + p_amount / 1500.0 where id = c.id;
end $$;

-- Only civic points are redeemable, only after NIN/BVN verification, max 2,500 points a week.
create or replace function redeem_cp(p_cp bigint, p_phone text) returns bigint
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); used bigint; rid bigint;
begin
  if p_cp not in (500, 2000) then perform _fail('Choose a 500 or 2,000 point voucher.'); end if;
  if c.kyc_level < 2 then perform _fail('Verify your identity (NIN or BVN) before redeeming rewards.'); end if;
  select coalesce(sum(cp), 0) into used from redemptions
   where citizen_id = c.id and status <> 'rejected' and created_at > now() - interval '7 days';
  if used + p_cp > 2500 then perform _fail(format('You can redeem %s more points this week.', 2500 - used)); end if;
  perform _move(c.id, 'cp', -p_cp, 'redemption');
  insert into redemptions (citizen_id, cp, naira, phone) values (c.id, p_cp, p_cp / 5, p_phone) returning id into rid;
  return rid;
end $$;

-- ---------- Household ----------

create or replace function buy_item(p_item text) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); it shop_items; have int;
begin
  select * into it from shop_items where id = p_item;
  if not found then perform _fail('That item is not for sale.'); end if;
  select coalesce(qty, 0) into have from citizen_items where citizen_id = c.id and item_id = p_item;
  have := coalesce(have, 0);
  if have >= it.max_qty then perform _fail('You already have the maximum of this.'); end if;
  if it.requires is not null and not exists (select 1 from citizen_items where citizen_id = c.id and item_id = it.requires) then
    perform _fail('Buy the previous upgrade first.');
  end if;
  perform _move(c.id, 'coins', -it.cost, 'purchase_item', p_item);
  insert into citizen_items (citizen_id, item_id, qty) values (c.id, p_item, 1)
  on conflict (citizen_id, item_id) do update set qty = citizen_items.qty + 1;
end $$;

-- ---------- Parties ----------

create or replace function join_party(p_party uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); pname text;
begin
  if exists (select 1 from party_members where citizen_id = c.id) then perform _fail('Leave your current party first.'); end if;
  select name into pname from parties where id = p_party;
  if pname is null then perform _fail('That party does not exist.'); end if;
  perform _move(c.id, 'coins', -200, 'party_dues', p_party::text);
  insert into party_members (citizen_id, party_id, joined_day) values (c.id, p_party, game_day());
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
  perform _news('INEC registers a new party, the ' || trim(p_name) || ', led by ' || c.display_name || '.');
  return pid;
end $$;

-- Decamping forfeits any open ticket. Chairs cannot decamp from their own party.
create or replace function leave_party() returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); m party_members;
begin
  select * into m from party_members where citizen_id = c.id;
  if not found then perform _fail('You are not in a party.'); end if;
  if m.role = 'chair' then perform _fail('Party chairs cannot decamp from their own party.'); end if;
  delete from candidates where citizen_id = c.id and votes is null;
  delete from party_members where citizen_id = c.id;
  perform _news(c.display_name || ' decamps from the ' || (select abbr from parties where id = m.party_id) || '.');
end $$;

-- ---------- Elections ----------

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
  perform _news(c.display_name || ' picks the ' || (select abbr from parties where id = m.party_id)
                || ' ticket for ' || _place(p_key) || '.');
end $$;

-- Every race has a legal spending limit. Buying coins can't push you past it.
create or replace function campaign(p_action text) returns numeric
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); cand candidates; e elections; ru office_rules; a campaign_actions; cost bigint; d numeric;
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
  return d;
end $$;

create or replace function withdraw_candidacy() returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me();
begin
  delete from candidates where citizen_id = c.id and votes is null;
  if not found then perform _fail('You are not running in any race.'); end if;
end $$;

-- ---------- Governing ----------

create or replace function _my_office(p_citizen uuid) returns text
language plpgsql security definer set search_path = public as $$
declare k text;
begin
  select key into k from offices where holder_id = p_citizen;
  if k is null then perform _fail('You do not hold an office.'); end if;
  return k;
end $$;

create or replace function start_project(p_stat text) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); k text := _my_office(c.id); cost bigint;
begin
  if p_stat not in ('roads','power','health','edu','security','economy') then perform _fail('Unknown project.'); end if;
  select ru.project_cost into cost from office_rules ru join jurisdictions j on j.type = ru.type where j.key = k;
  perform _use_energy(c.id, 1);
  update jurisdictions set treasury = treasury - cost where key = k and treasury >= cost;
  if not found then perform _fail('The treasury is empty. Wait for the monthly allocation.'); end if;
  insert into projects (key, stat, gain, ready_day, started_by)
  values (k, p_stat, 9 + floor(random() * 6), game_day() + 3, c.id);
end $$;

create or replace function town_hall() returns numeric
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); k text := _my_office(c.id); d numeric := 2 + floor(random() * 6);
begin
  perform _use_energy(c.id, 1);
  update jurisdictions set mood = mood + d where key = k;
  update citizens set rep = rep + 0.5 where id = c.id;
  return d;
end $$;

create or replace function pay_salaries() returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); k text := _my_office(c.id); cost bigint;
begin
  select round(ru.project_cost * 0.8) into cost from office_rules ru join jurisdictions j on j.type = ru.type where j.key = k;
  update jurisdictions set treasury = treasury - cost, last_salary_day = game_day(), mood = mood + 8
   where key = k and treasury >= cost;
  if not found then perform _fail('Not enough in the treasury for salaries.'); end if;
end $$;

-- ---------- Payments (service role only) ----------

create or replace function create_purchase(p_citizen uuid, p_pack text, p_reference text) returns coin_packs
language plpgsql security definer set search_path = public as $$
declare pk coin_packs;
begin
  select * into pk from coin_packs where id = p_pack;
  if not found then perform _fail('Unknown coin pack.'); end if;
  insert into purchases (reference, citizen_id, pack_id, kobo, coins) values (p_reference, p_citizen, p_pack, pk.kobo, pk.coins);
  return pk;
end $$;

-- Idempotent: Paystack retries webhooks, so a paid reference is credited exactly once.
create or replace function credit_purchase(p_reference text, p_kobo bigint) returns boolean
language plpgsql security definer set search_path = public as $$
declare p purchases;
begin
  select * into p from purchases where reference = p_reference for update;
  if not found then return false; end if;
  if p.status = 'paid' then return true; end if;
  if p_kobo <> p.kobo then
    update purchases set status = 'failed' where reference = p_reference;
    return false;
  end if;
  update purchases set status = 'paid', paid_at = now() where reference = p_reference;
  update wallets set purchased_total = purchased_total + p.coins where citizen_id = p.citizen_id;
  perform _move(p.citizen_id, 'coins', p.coins, 'coin_purchase', p_reference, 'purchase:' || p_reference);
  return true;
end $$;

-- ---------- Grants ----------
-- Supabase grants EXECUTE to everyone by default. Lock it down, then open only the player verbs.

revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function
  game_day(), register_citizen(text, text), claim_daily(), stash_coins(bigint), unstash_coins(bigint),
  gift_coins(uuid, bigint), redeem_cp(bigint, text), buy_item(text), join_party(uuid),
  create_party(text, text, text), leave_party(), declare_candidacy(text), campaign(text),
  withdraw_candidacy(), start_project(text), town_hall(), pay_salaries()
to authenticated;
-- credit_ad_reward, create_purchase and credit_purchase are called by edge functions with the service role.
