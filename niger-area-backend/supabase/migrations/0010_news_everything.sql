-- Niger Area: every sanction and withdrawal makes the news.
-- News gets a category so the page can filter: election, party, law, government, announcement, general.

alter table news add column kind text not null default 'general';
update news set kind = case
  when body like 'INEC declares%' or body like 'No candidate filed%' or body like '%ticket for%' then 'election'
  when body like '%joins the%' or body like '%decamps%' or body like 'INEC registers a new party%' then 'party'
  when body like '%EFCC%' or body like '%arrest%' or body like '%detained%' or body like '%bail%' or body like '%sanction%' then 'law'
  when body like '📢%' then 'announcement'
  when body like 'Commissioned%' or body like 'FAAC%' then 'government'
  else 'general' end;

create or replace function _news_kind(p_body text) returns text
language sql immutable set search_path = public as $$
  select case
    when p_body like 'INEC declares%' or p_body like 'No candidate filed%' or p_body like '%ticket for%' or p_body like '%withdraws from%' then 'election'
    when p_body like '%joins the%' or p_body like '%decamps%' or p_body like 'INEC registers a new party%' then 'party'
    when p_body like '%EFCC%' or p_body like '%arrest%' or p_body like '%detained%' or p_body like '%bail%'
      or p_body like '%sanction%' or p_body like '%suspended%' or p_body like '%muted%' or p_body like '%fined%'
      or p_body like '%warned%' or p_body like '%banned%' or p_body like '%reinstated%' then 'law'
    when p_body like '📢%' then 'announcement'
    when p_body like 'Commissioned%' or p_body like 'FAAC%' or p_body like 'LG Chairman %' or p_body like 'Governor %'
      or p_body like 'President %' or p_body like 'Senator %' then 'government'
    else 'general' end
$$;

-- Every insert gets its category automatically, including from the daily tick.
create or replace function _news_classify() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.kind = 'general' then new.kind := _news_kind(new.body); end if;
  return new;
end $$;
create trigger news_classify before insert on news for each row execute function _news_classify();

create or replace function admin_sanction(p_target uuid, p_kind text, p_reason text, p_days int default null, p_amount bigint default null)
returns void
language plpgsql security definer set search_path = public as $$
declare n text; until_at timestamptz := case when p_days is not null then now() + make_interval(days => p_days) end; headline text;
begin
  perform _admin_only();
  select display_name into n from citizens where id = p_target;
  if n is null then perform _fail('Player not found.'); end if;
  if coalesce(trim(p_reason), '') = '' then perform _fail('Give a reason. The player will see it.'); end if;
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

create or replace function withdraw_candidacy() returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); k text;
begin
  select e.key into k from candidates ca join elections e on e.id = ca.election_id where ca.citizen_id = c.id and ca.votes is null;
  delete from candidates where citizen_id = c.id and votes is null;
  if not found then perform _fail('You are not running in any race.'); end if;
  perform _news(c.display_name || ' withdraws from the race for ' || _place(k) || '.');
end $$;

-- Election results now name the runner-up and the margin.
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
  update offices set holder_id = null, holder_party = null where holder_id = win.citizen_id and key <> e.key;
  update offices set holder_id = win.citizen_id, holder_party = win.party_id, term_ends_day = p_day + ru.term_days
   where key = e.key;
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
