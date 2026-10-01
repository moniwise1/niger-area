-- Niger Area: the daily tick. Runs once a day from pg_cron (0005) and is never callable by players.

create or replace function _resolve_election(p_election uuid, p_day int) returns void
language plpgsql security definer set search_path = public as $$
declare e elections; j jurisdictions; ru office_rules; n int; v_turnout bigint; win candidates; wname text;
begin
  select * into e from elections where id = p_election for update;
  select * into j from jurisdictions where key = e.key;
  select * into ru from office_rules where type = j.type;
  select count(*) into n from candidates where election_id = e.id;

  if n = 0 then
    -- Nobody filed: a caretaker committee runs things and INEC reschedules in 14 days.
    update elections set status = 'closed', turnout = 0 where id = e.id;
    update offices set holder_id = null, holder_party = null, term_ends_day = p_day + 14 where key = e.key;
    insert into elections (key, poll_day) values (e.key, p_day + 14);
    insert into news (day, body) values (p_day, 'No candidate filed for ' || _place(e.key)
      || '. A caretaker committee takes over until fresh polls in 14 days.');
    return;
  end if;

  v_turnout := floor((ru.voters_min + random() * (ru.voters_max - ru.voters_min)) * (0.28 + random() * 0.14));

  with w as (
    select citizen_id,
           greatest(1, popularity
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
  -- One office at a time: winning a new seat vacates the old one to a caretaker.
  update offices set holder_id = null, holder_party = null where holder_id = win.citizen_id and key <> e.key;
  update offices set holder_id = win.citizen_id, holder_party = win.party_id, term_ends_day = p_day + ru.term_days
   where key = e.key;
  update jurisdictions set mood = 10, last_salary_day = p_day where key = e.key;
  update citizens set offices_held = offices_held + 1, rep = rep + 8 where id = win.citizen_id;
  perform _move(win.citizen_id, 'cp', 500, 'election_win', e.key, 'win:' || e.id);
  insert into elections (key, poll_day) values (e.key, p_day + ru.term_days);
  insert into news (day, body) values (p_day, 'INEC declares ' || wname || ' ('
    || (select abbr from parties where id = win.party_id) || ') winner: ' || _place(e.key)
    || ', with ' || to_char(win.votes, 'FM999,999,999') || ' votes.');
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
  update offices set holder_id = null, holder_party = null where holder_id = p_citizen;
  delete from candidates where citizen_id = p_citizen and votes is null;
  update citizens set scandal = 15, integrity = greatest(0, integrity - 10), rep = rep * 0.5 where id = p_citizen;
  select display_name into name from citizens where id = p_citizen;
  insert into news (day, body) values (p_day, 'EFCC operatives raid the home of ' || name || '.');
end $$;

create or replace function advance_day() returns int
language plpgsql security definer set search_path = public as $$
declare d int; r record;
begin
  update game_clock set day = day + 1 where id = 1 returning day into d;

  -- Finished projects.
  for r in select * from projects where not done and ready_day <= d loop
    execute format('update jurisdictions set %1$I = least(100, %1$I + $1), mood = mood + 3 where key = $2', r.stat)
      using r.gain, r.key;
    update projects set done = true where id = r.id;
    if r.started_by is not null then update citizens set rep = rep + 0.3 where id = r.started_by; end if;
    insert into news (day, body) values (d, 'Commissioned: a new ' || r.stat || ' project. ' || _place(r.key) || '.');
  end loop;

  -- Everything wears out a little each day.
  update jurisdictions set mood = mood * 0.9,
    roads = greatest(0, roads - 0.3), power = greatest(0, power - 0.3), health = greatest(0, health - 0.3),
    edu = greatest(0, edu - 0.3), security = greatest(0, security - 0.3), economy = greatest(0, economy - 0.3);

  -- Office holders: salary, plus civic points and reputation for governing well.
  for r in select o.key, o.holder_id, ru.salary
             from offices o join jurisdictions j on j.key = o.key join office_rules ru on ru.type = j.type
            where o.holder_id is not null loop
    perform _move(r.holder_id, 'coins', r.salary, 'salary', r.key, 'salary:' || r.key || ':' || d);
    if _approval(r.key) >= 60 then
      perform _move(r.holder_id, 'cp', 50, 'good_governance', r.key, 'gg:' || r.key || ':' || d);
      update citizens set rep = rep + 0.3 where id = r.holder_id;
    end if;
  end loop;

  -- Business income.
  for r in select ci.citizen_id, sum(ci.qty * s.daily_income)::bigint as inc
             from citizen_items ci join shop_items s on s.id = ci.item_id
            where s.daily_income > 0 group by ci.citizen_id loop
    perform _move(r.citizen_id, 'coins', r.inc, 'business_income', null, 'biz:' || r.citizen_id || ':' || d);
  end loop;

  -- Reputation for showing up: only citizens who checked in yesterday.
  update citizens c set rep = rep + 0.2 from daily_limits l
   where l.citizen_id = c.id and l.day = d - 1 and l.claimed;
  update citizens set scandal = greatest(0, scandal - 0.5) where scandal > 0;

  -- Monthly FAAC allocation, and strikes where salaries went unpaid.
  if d % 30 = 0 then
    update jurisdictions j set treasury = treasury + round(ru.alloc * (select alloc_boost from game_clock where id = 1))
      from office_rules ru where ru.type = j.type;
    update game_clock set alloc_boost = 1 where id = 1;
    update jurisdictions set mood = mood - 15
     where key in (select key from offices where holder_id is not null) and d - last_salary_day > 30;
    insert into news (day, body) values (d, 'FAAC shares the monthly federation allocation.');
  end if;

  -- Polls due today.
  for r in select id from elections where status = 'open' and poll_day <= d loop
    perform _resolve_election(r.id, d);
  end loop;

  -- EFCC: the higher your scandal score above 40, the likelier a raid.
  for r in select id, scandal from citizens where scandal > 40 loop
    if random() < (r.scandal - 40) / 180 then perform _efcc_raid(r.id, d); end if;
  end loop;

  return d;
end $$;

revoke execute on function advance_day(), _resolve_election(uuid, int), _efcc_raid(uuid, int)
  from public, anon, authenticated;
