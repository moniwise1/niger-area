-- Niger Area: owner accounts run the backend only and cannot register as citizens.

create or replace function register_citizen(p_name text, p_lga text) returns void
language plpgsql security definer set search_path = public as $$
declare s text; v_ip text := _client_ip();
begin
  if auth.uid() is null then perform _fail('Sign in first.'); end if;
  if is_admin() then perform _fail('Owner accounts run the backend and cannot register as citizens.'); end if;
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
