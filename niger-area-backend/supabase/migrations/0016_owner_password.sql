-- Niger Area: owner password on top of the normal login.
--   * The owner sets it once (bcrypt-hashed with pgcrypto; nobody can read it back).
--   * Unlocking opens owner powers for 2 hours, only for the current login session.
--   * 5 wrong attempts lock owner access for 15 minutes. Every attempt is logged with its IP.
--   * Every admin_* function checks the unlock through _admin_only().
-- Wrong passwords return {ok:false} instead of raising an error: an error would roll back
-- the transaction and erase the failed-attempt counter and the log entry.

create extension if not exists pgcrypto with schema extensions;

create table admin_secrets (
  user_id uuid primary key references auth.users on delete cascade,
  pass_hash text not null,
  set_at timestamptz not null default now(),
  failed int not null default 0,
  locked_until timestamptz
);
create table admin_sessions (
  user_id uuid not null references auth.users on delete cascade,
  session_id text not null,
  expires_at timestamptz not null,
  ip text,
  created_at timestamptz not null default now(),
  primary key (user_id, session_id)
);
create table admin_login_log (
  id bigserial primary key,
  user_id uuid references auth.users on delete cascade,
  ok boolean not null,
  what text not null,
  ip text,
  at timestamptz not null default now()
);
alter table admin_secrets enable row level security;
alter table admin_sessions enable row level security;
alter table admin_login_log enable row level security;
-- No policies: no client can read any of these tables.

create or replace function _session_id() returns text
language sql stable set search_path = public as $$
  select coalesce(auth.jwt() ->> 'session_id', '')
$$;

create or replace function _admin_only() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then perform _fail('Owner access only.'); end if;
  if not exists (select 1 from admin_sessions
                  where user_id = auth.uid() and session_id = _session_id() and expires_at > now()) then
    perform _fail('Owner password required.');
  end if;
end $$;

create or replace function admin_password_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare s admin_secrets; e timestamptz;
begin
  if not is_admin() then perform _fail('Owner access only.'); end if;
  select * into s from admin_secrets where user_id = auth.uid();
  select expires_at into e from admin_sessions where user_id = auth.uid() and session_id = _session_id() and expires_at > now();
  return jsonb_build_object('has_password', s.user_id is not null, 'unlocked', e is not null, 'expires_at', e,
                            'locked_until', case when s.locked_until > now() then s.locked_until end);
end $$;

-- Records a wrong attempt and locks after 5. Returns the result for the page to show.
create or replace function _admin_wrong(p_what text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s admin_secrets;
begin
  update admin_secrets
     set failed = case when failed + 1 >= 5 then 0 else failed + 1 end,
         locked_until = case when failed + 1 >= 5 then now() + interval '15 minutes' else locked_until end
   where user_id = auth.uid() returning * into s;
  insert into admin_login_log (user_id, ok, what, ip) values (auth.uid(), false, p_what, _client_ip());
  if s.locked_until > now() then
    return jsonb_build_object('ok', false, 'message', 'Too many wrong attempts. Owner access is locked until '
      || to_char(s.locked_until at time zone 'Africa/Lagos', 'HH24:MI') || ' WAT.');
  end if;
  return jsonb_build_object('ok', false, 'message', format('Wrong owner password. %s attempt%s left before a 15-minute lock.', 5 - s.failed, case when 5 - s.failed = 1 then '' else 's' end));
end $$;

-- First time: no current password needed. Afterwards the current one is required.
create or replace function admin_set_password(p_new text, p_old text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s admin_secrets;
begin
  if not is_admin() then perform _fail('Owner access only.'); end if;
  if char_length(coalesce(p_new, '')) < 10 then perform _fail('Use at least 10 characters.'); end if;
  if p_new !~ '[0-9]' or p_new !~ '[A-Za-z]' then perform _fail('Use both letters and numbers.'); end if;
  select * into s from admin_secrets where user_id = auth.uid() for update;
  if found then
    if s.locked_until > now() then
      return jsonb_build_object('ok', false, 'message', 'Too many wrong attempts. Try again after '
        || to_char(s.locked_until at time zone 'Africa/Lagos', 'HH24:MI') || ' WAT.');
    end if;
    if p_old is null or crypt(p_old, s.pass_hash) <> s.pass_hash then return _admin_wrong('change password'); end if;
    update admin_secrets set pass_hash = crypt(p_new, gen_salt('bf', 10)), set_at = now(), failed = 0, locked_until = null
     where user_id = auth.uid();
  else
    insert into admin_secrets (user_id, pass_hash) values (auth.uid(), crypt(p_new, gen_salt('bf', 10)));
  end if;
  -- A new password signs out every other unlocked session.
  delete from admin_sessions where user_id = auth.uid();
  insert into admin_sessions (user_id, session_id, expires_at, ip) values (auth.uid(), _session_id(), now() + interval '2 hours', _client_ip());
  insert into admin_login_log (user_id, ok, what, ip)
  values (auth.uid(), true, case when s.user_id is null then 'set password' else 'change password' end, _client_ip());
  return jsonb_build_object('ok', true);
end $$;

create or replace function admin_unlock(p_password text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s admin_secrets; until_at timestamptz := now() + interval '2 hours';
begin
  if not is_admin() then perform _fail('Owner access only.'); end if;
  select * into s from admin_secrets where user_id = auth.uid() for update;
  if not found then return jsonb_build_object('ok', false, 'message', 'Set your owner password first.'); end if;
  if s.locked_until > now() then
    return jsonb_build_object('ok', false, 'message', 'Too many wrong attempts. Owner access is locked until '
      || to_char(s.locked_until at time zone 'Africa/Lagos', 'HH24:MI') || ' WAT.');
  end if;
  if crypt(coalesce(p_password, ''), s.pass_hash) <> s.pass_hash then return _admin_wrong('unlock'); end if;
  update admin_secrets set failed = 0, locked_until = null where user_id = auth.uid();
  insert into admin_sessions (user_id, session_id, expires_at, ip) values (auth.uid(), _session_id(), until_at, _client_ip())
  on conflict (user_id, session_id) do update set expires_at = excluded.expires_at, ip = excluded.ip;
  insert into admin_login_log (user_id, ok, what, ip) values (auth.uid(), true, 'unlock', _client_ip());
  return jsonb_build_object('ok', true, 'expires_at', until_at);
end $$;

create or replace function admin_lock() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from admin_sessions where user_id = auth.uid();
end $$;

create or replace function admin_login_history() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _admin_only();
  return (select coalesce(jsonb_agg(x order by x.id desc), '[]') from (
    select id, ok, what, ip, at from admin_login_log where user_id = auth.uid() order by id desc limit 50) x);
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
  admin_password_status(), admin_set_password(text, text), admin_unlock(text), admin_lock(), admin_login_history(),
  admin_dashboard(), admin_players(text, int), admin_player(uuid), admin_sanction(uuid, text, text, int, bigint),
  admin_sanctions_log(int), admin_redemptions(), admin_resolve_redemption(bigint, boolean), admin_posts(int),
  admin_delete_post(bigint), admin_set_playtest(boolean), admin_broadcast(text),
  admin_ip_report(), admin_allow_ip(text, text), admin_release(uuid),
  admin_reports(), admin_close_report(bigint), admin_report_messages(bigint)
to authenticated;
