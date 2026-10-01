-- Niger Area: profiles, connections, private chat and reports.

alter table citizens add column avatar_url text;
alter table citizens add column bio text check (char_length(bio) <= 160);
alter table citizens add column dm_policy text not null default 'everyone' check (dm_policy in ('everyone', 'connections', 'nobody'));

create table connections (
  requester_id uuid not null references citizens on delete cascade,
  addressee_id uuid not null references citizens on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);
create unique index connections_pair on connections (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create table messages (
  id bigserial primary key,
  sender_id uuid not null references citizens on delete cascade,
  recipient_id uuid not null references citizens on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index messages_pair_idx on messages (least(sender_id, recipient_id), greatest(sender_id, recipient_id), id desc);
create index messages_inbox_idx on messages (recipient_id, read_at);

create table reports (
  id bigserial primary key,
  reporter_id uuid not null references citizens on delete cascade,
  target_id uuid not null references citizens on delete cascade,
  reason text not null check (char_length(reason) between 3 and 500),
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now()
);

alter table connections enable row level security;
alter table messages enable row level security;
alter table reports enable row level security;
create policy read_mine on connections for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());
create policy read_mine on messages for select to authenticated
  using (sender_id = auth.uid() or recipient_id = auth.uid());
-- reports: owner only, through admin_reports().

create or replace function _connected(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from connections where status = 'accepted'
                  and ((requester_id = a and addressee_id = b) or (requester_id = b and addressee_id = a)))
$$;

-- ---------- Profile ----------
create or replace function update_profile(p_bio text, p_dm_policy text) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me();
begin
  if p_dm_policy not in ('everyone', 'connections', 'nobody') then perform _fail('Choose who can message you.'); end if;
  if char_length(coalesce(p_bio, '')) > 160 then perform _fail('Keep your bio under 160 characters.'); end if;
  update citizens set bio = nullif(trim(p_bio), ''), dm_policy = p_dm_policy where id = c.id;
end $$;

-- Only pictures uploaded to your own folder in the avatars bucket are accepted.
create or replace function set_avatar(p_url text) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me();
begin
  if p_url is not null and p_url !~ ('/storage/v1/object/public/avatars/' || c.id::text || '/[A-Za-z0-9._-]+$') then
    perform _fail('Upload your picture through the game.');
  end if;
  update citizens set avatar_url = p_url where id = c.id;
end $$;

-- ---------- Connections ----------
create or replace function request_connection(p_target uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); n text; existing connections;
begin
  if p_target = c.id then perform _fail('You cannot connect with yourself.'); end if;
  select display_name into n from citizens where id = p_target and not banned;
  if n is null then perform _fail('That citizen was not found.'); end if;
  select * into existing from connections
   where (requester_id = c.id and addressee_id = p_target) or (requester_id = p_target and addressee_id = c.id);
  if found then
    if existing.status = 'accepted' then perform _fail('You are already connected.'); end if;
    if existing.requester_id = c.id then perform _fail('Your request is still waiting for a reply.'); end if;
    -- They already asked you: accept it.
    update connections set status = 'accepted', accepted_at = now() where requester_id = p_target and addressee_id = c.id;
    return 'accepted';
  end if;
  if (select count(*) from connections where requester_id = c.id and status = 'pending') >= 50 then
    perform _fail('You have 50 requests waiting. Wait for some replies first.');
  end if;
  insert into connections (requester_id, addressee_id) values (c.id, p_target);
  return 'requested';
end $$;

create or replace function respond_connection(p_requester uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me();
begin
  if p_accept then
    update connections set status = 'accepted', accepted_at = now()
     where requester_id = p_requester and addressee_id = c.id and status = 'pending';
  else
    delete from connections where requester_id = p_requester and addressee_id = c.id and status = 'pending';
  end if;
  if not found then perform _fail('That request is no longer pending.'); end if;
end $$;

create or replace function remove_connection(p_other uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me();
begin
  delete from connections where (requester_id = c.id and addressee_id = p_other) or (requester_id = p_other and addressee_id = c.id);
end $$;

-- ---------- Private chat ----------
create or replace function send_message(p_to uuid, p_body text) returns bigint
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); r citizens; mid bigint; recent int;
begin
  if c.muted_until > now() then
    perform _fail('You are muted until ' || to_char(c.muted_until at time zone 'Africa/Lagos', 'DD Mon HH24:MI') || ' WAT.');
  end if;
  p_body := trim(p_body);
  if char_length(p_body) < 1 or char_length(p_body) > 1000 then perform _fail('Messages must be 1 to 1,000 characters.'); end if;
  select * into r from citizens where id = p_to;
  if not found or r.banned then perform _fail('That citizen was not found.'); end if;
  if r.id = c.id then perform _fail('You cannot message yourself.'); end if;
  -- Replies are always allowed once the other person has written to you.
  if not exists (select 1 from messages where sender_id = r.id and recipient_id = c.id) then
    if r.dm_policy = 'nobody' then perform _fail(r.display_name || ' is not accepting messages.'); end if;
    if r.dm_policy = 'connections' and not _connected(c.id, r.id) then
      perform _fail(r.display_name || ' only accepts messages from connections. Send a connection request first.');
    end if;
  end if;
  select count(*) into recent from messages where sender_id = c.id and created_at > now() - interval '1 minute';
  if recent >= 10 then perform _fail('Slow down. You are sending messages too fast.'); end if;
  insert into messages (sender_id, recipient_id, body) values (c.id, r.id, p_body) returning id into mid;
  return mid;
end $$;

create or replace function mark_read(p_other uuid) returns void
language sql security definer set search_path = public as $$
  update messages set read_at = now() where recipient_id = auth.uid() and sender_id = p_other and read_at is null
$$;

-- One row per conversation, newest first, with unread counts.
create or replace function my_conversations() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x.last_at desc), '[]') from (
    select other as id, c.display_name as name, c.avatar_url,
           max(m.created_at) as last_at,
           (array_agg(m.body order by m.id desc))[1] as last_body,
           count(*) filter (where m.recipient_id = auth.uid() and m.read_at is null) as unread
      from (select *, case when sender_id = auth.uid() then recipient_id else sender_id end as other
              from messages where sender_id = auth.uid() or recipient_id = auth.uid()) m
      join citizens c on c.id = m.other
     group by other, c.display_name, c.avatar_url) x
$$;

-- ---------- Reports ----------
create or replace function report_citizen(p_target uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me();
begin
  if p_target = c.id then perform _fail('You cannot report yourself.'); end if;
  if (select count(*) from reports where reporter_id = c.id and created_at > now() - interval '1 day') >= 10 then
    perform _fail('You have sent many reports today. The team will review them.');
  end if;
  insert into reports (reporter_id, target_id, reason) values (c.id, p_target, trim(p_reason));
end $$;

create or replace function admin_reports() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  return (select coalesce(jsonb_agg(x order by x.id desc), '[]') from (
    select r.*, a.display_name as reporter, t.display_name as target,
           (select count(*) from reports r2 where r2.target_id = r.target_id) as times_reported
      from reports r join citizens a on a.id = r.reporter_id join citizens t on t.id = r.target_id
     where r.status = 'open' order by r.id desc limit 200) x);
end $$;

create or replace function admin_close_report(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  update reports set status = 'closed' where id = p_id;
end $$;

-- Reported conversations only: the owner can read messages between a reported player and the reporter.
create or replace function admin_report_messages(p_report bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r reports;
begin
  perform _admin_only();
  select * into r from reports where id = p_report;
  return (select coalesce(jsonb_agg(m order by m.id), '[]') from (
    select id, sender_id, body, created_at from messages
     where (sender_id = r.reporter_id and recipient_id = r.target_id) or (sender_id = r.target_id and recipient_id = r.reporter_id)
     order by id desc limit 100) m);
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
  admin_dashboard(), admin_players(text, int), admin_player(uuid), admin_sanction(uuid, text, text, int, bigint),
  admin_sanctions_log(int), admin_redemptions(), admin_resolve_redemption(bigint, boolean), admin_posts(int),
  admin_delete_post(bigint), admin_set_playtest(boolean), admin_broadcast(text),
  admin_ip_report(), admin_allow_ip(text, text), admin_release(uuid),
  admin_reports(), admin_close_report(bigint), admin_report_messages(bigint)
to authenticated;
