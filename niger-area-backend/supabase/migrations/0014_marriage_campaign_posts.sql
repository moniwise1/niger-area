-- Niger Area: marriage between players, campaign posts, likes, live vote counts.

alter table citizens add column show_spouse boolean not null default true;

create table proposals (
  proposer_id uuid not null references citizens on delete cascade,
  target_id   uuid not null references citizens on delete cascade,
  note text check (char_length(note) <= 200),
  created_at timestamptz not null default now(),
  primary key (proposer_id, target_id),
  check (proposer_id <> target_id)
);
create table marriages (
  id bigserial primary key,
  a_id uuid not null references citizens on delete cascade,
  b_id uuid not null references citizens on delete cascade,
  married_at timestamptz not null default now(),
  ended_at timestamptz
);
alter table proposals enable row level security;
alter table marriages enable row level security;
create policy read_mine on proposals for select to authenticated using (proposer_id = auth.uid() or target_id = auth.uid());
create policy read_mine on marriages for select to authenticated using (a_id = auth.uid() or b_id = auth.uid());

alter table posts add column election_id uuid references elections on delete set null;
alter table posts add column likes int not null default 0;
create table post_likes (
  post_id bigint not null references posts on delete cascade,
  citizen_id uuid not null references citizens on delete cascade,
  primary key (post_id, citizen_id)
);
alter table post_likes enable row level security;
create policy read_own on post_likes for select to authenticated using (citizen_id = auth.uid());

-- Who you are married to lives only in marriages (private to the couple).
create or replace function _spouse_of(p_citizen uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select case when a_id = p_citizen then b_id else a_id end from marriages
   where ended_at is null and (a_id = p_citizen or b_id = p_citizen) limit 1
$$;

-- Shown on a profile only if that citizen chose to show it.
create or replace function public_spouse(p_citizen uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when c.show_spouse and s.id is not null
              then jsonb_build_object('id', s.id, 'name', s.display_name, 'avatar_url', s.avatar_url) end
    from citizens c left join citizens s on s.id = _spouse_of(c.id) where c.id = p_citizen
$$;

-- ---------- Marriage ----------
-- The proposer pays the 6,000 wedding fee up front; it is refunded if the proposal is declined or withdrawn.
create or replace function propose(p_target uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); t citizens;
begin
  select * into t from citizens where id = p_target;
  if not found or t.banned then perform _fail('That citizen was not found.'); end if;
  if t.id = c.id then perform _fail('You cannot marry yourself.'); end if;
  if _spouse_of(c.id) is not null then perform _fail('You are already married.'); end if;
  if _spouse_of(t.id) is not null then perform _fail(t.display_name || ' is already married.'); end if;
  if exists (select 1 from proposals where proposer_id = c.id) then perform _fail('You already have a proposal waiting for an answer.'); end if;
  perform _move(c.id, 'coins', -6000, 'wedding_fee', p_target::text);
  insert into proposals (proposer_id, target_id, note) values (c.id, t.id, nullif(trim(p_note), ''));
end $$;

create or replace function _refund_proposal(p_proposer uuid, p_target uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from proposals where proposer_id = p_proposer and target_id = p_target;
  if found then perform _move(p_proposer, 'coins', 6000, 'wedding_refund', p_reason); end if;
end $$;

create or replace function withdraw_proposal() returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); t uuid;
begin
  select target_id into t from proposals where proposer_id = c.id;
  if t is null then perform _fail('You have no proposal waiting.'); end if;
  perform _refund_proposal(c.id, t, 'withdrawn');
end $$;

create or replace function answer_proposal(p_proposer uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); p citizens; place text; other uuid;
begin
  if not exists (select 1 from proposals where proposer_id = p_proposer and target_id = c.id) then
    perform _fail('That proposal is no longer open.');
  end if;
  if not p_accept then perform _refund_proposal(p_proposer, c.id, 'declined'); return; end if;
  select * into p from citizens where id = p_proposer for update;
  if _spouse_of(c.id) is not null or _spouse_of(p.id) is not null then
    perform _refund_proposal(p_proposer, c.id, 'already married');
    perform _fail('One of you is already married.');
  end if;
  delete from proposals where proposer_id = p_proposer and target_id = c.id;
  -- Any other open proposals involving either person are refunded.
  for other in select proposer_id from proposals where target_id in (c.id, p.id) loop
    perform _refund_proposal(other, (select target_id from proposals where proposer_id = other), 'they married someone else');
  end loop;
  for other in select target_id from proposals where proposer_id = c.id loop
    perform _refund_proposal(c.id, other, 'you married someone else');
  end loop;
  insert into marriages (a_id, b_id) values (p.id, c.id);
  insert into citizen_items (citizen_id, item_id, qty) values (c.id, 'spouse', 1), (p.id, 'spouse', 1) on conflict do nothing;
  if c.show_spouse and p.show_spouse then
    select name into place from lgas where id = p.lga_id;
    perform _news(p.display_name || ' and ' || c.display_name || ' wed in a colourful ceremony in ' || place || '. Aso-ebi everywhere!');
  end if;
end $$;

create or replace function divorce() returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); s citizens;
begin
  select * into s from citizens where id = _spouse_of(c.id) for update;
  if not found then perform _fail('You are not married.'); end if;
  update marriages set ended_at = now() where ended_at is null and ((a_id = c.id and b_id = s.id) or (a_id = s.id and b_id = c.id));
  delete from citizen_items where item_id = 'spouse' and citizen_id in (c.id, s.id);
  if c.show_spouse and s.show_spouse then
    perform _news(c.display_name || ' and ' || s.display_name || ' have separated.');
  end if;
end $$;

create or replace function set_show_spouse(p_show boolean) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me();
begin
  update citizens set show_spouse = p_show where id = c.id;
end $$;

-- Marriage is no longer a shop item.
create or replace function buy_item(p_item text) returns void
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); it shop_items; have int;
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
  perform _move(c.id, 'coins', -it.cost, 'purchase_item', p_item);
  insert into citizen_items (citizen_id, item_id, qty) values (c.id, p_item, 1)
  on conflict (citizen_id, item_id) do update set qty = citizen_items.qty + 1;
  if it.kind = 'house' then perform _award(c.id, 'homeowner'); end if;
  if p_item = 'house5' then perform _award(c.id, 'mansion'); end if;
  if it.kind = 'business' then perform _award(c.id, 'entrepreneur'); end if;
  if p_item = 'station' then perform _award(c.id, 'oil_baron'); end if;
end $$;

-- ---------- Campaign posts and likes ----------
-- A candidate's post carries a Vote button for the race they are in.
create or replace function post_campaign(p_body text) returns bigint
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); cand candidates; e elections; pid bigint; last timestamptz;
begin
  if c.muted_until > now() then perform _fail('You are muted.'); end if;
  select * into cand from candidates where citizen_id = c.id and votes is null;
  if not found then perform _fail('Only candidates can post campaign messages.'); end if;
  select * into e from elections where id = cand.election_id;
  p_body := trim(p_body);
  if char_length(p_body) < 1 or char_length(p_body) > 280 then perform _fail('Posts must be 1 to 280 characters.'); end if;
  select max(created_at) into last from posts where author_id = c.id and election_id is not null;
  if last > now() - interval '30 minutes' then perform _fail('You can post one campaign message every 30 minutes.'); end if;
  insert into posts (author_id, channel, body, election_id) values (c.id, 'national', p_body, e.id) returning id into pid;
  update citizens set posts_total = posts_total + 1 where id = c.id;
  update daily_limits set posted = true where citizen_id = c.id and day = game_day();
  return pid;
end $$;

create or replace function toggle_like(p_post bigint) returns int
language plpgsql security definer set search_path = public as $$
declare c citizens := _me(); n int;
begin
  if not exists (select 1 from posts where id = p_post and not deleted
                   and (channel = 'national' or exists (select 1 from party_members m where m.citizen_id = c.id and m.party_id::text = posts.channel))) then
    perform _fail('That post is not available.');
  end if;
  delete from post_likes where post_id = p_post and citizen_id = c.id;
  if found then
    update posts set likes = greatest(0, likes - 1) where id = p_post returning likes into n;
  else
    insert into post_likes values (p_post, c.id);
    update posts set likes = likes + 1 where id = p_post returning likes into n;
  end if;
  return n;
end $$;

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    execute 'alter publication supabase_realtime add table public.candidates';
  end if;
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
  admin_dashboard(), admin_players(text, int), admin_player(uuid), admin_sanction(uuid, text, text, int, bigint),
  admin_sanctions_log(int), admin_redemptions(), admin_resolve_redemption(bigint, boolean), admin_posts(int),
  admin_delete_post(bigint), admin_set_playtest(boolean), admin_broadcast(text),
  admin_ip_report(), admin_allow_ip(text, text), admin_release(uuid),
  admin_reports(), admin_close_report(bigint), admin_report_messages(bigint)
to authenticated;
