-- Playtest mode: while on, new citizens count as phone-verified (SMS isn't wired up yet)
-- and any signed-in player can skip the clock forward one day. Turn OFF before launch:
--   update game_clock set playtest = false;
alter table game_clock add column playtest boolean not null default false;
update game_clock set playtest = true where id = 1;

create or replace function register_citizen(p_name text, p_lga text) returns void
language plpgsql security definer set search_path = public as $$
declare s text;
begin
  if auth.uid() is null then perform _fail('Sign in first.'); end if;
  if exists (select 1 from citizens where id = auth.uid()) then perform _fail('You are already a citizen.'); end if;
  select state_id into s from lgas where id = p_lga;
  if s is null then perform _fail('Unknown local government.'); end if;
  insert into citizens (id, display_name, state_id, lga_id, energy_day, kyc_level)
  values (auth.uid(), trim(p_name), s, p_lga, game_day(),
          case when (select playtest from game_clock where id = 1) then 1 else 0 end);
  insert into wallets (citizen_id, coins) values (auth.uid(), 0);
  perform _move(auth.uid(), 'coins', 1500, 'welcome_bonus', null, 'welcome:' || auth.uid());
  perform _news(trim(p_name) || ' registers as a citizen of Niger Area.');
end $$;

create or replace function playtest_advance_day() returns int
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not exists (select 1 from citizens where id = auth.uid()) then
    perform _fail('Register as a citizen first.');
  end if;
  if not (select playtest from game_clock where id = 1) then
    perform _fail('Skipping days is only allowed during the playtest.');
  end if;
  perform _news('A playtester skips the clock forward one day.');
  return advance_day();
end $$;

revoke execute on function playtest_advance_day() from public, anon;
grant execute on function playtest_advance_day() to authenticated;
revoke execute on function register_citizen(text, text) from public, anon;
grant execute on function register_citizen(text, text) to authenticated;
