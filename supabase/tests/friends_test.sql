-- Tester venne-backenden. Stopper ved første fejl (psql -v ON_ERROR_STOP=1).
\set QUIET on
\o /dev/null
insert into auth.users (id) values
    ('00000000-0000-0000-0000-00000000000a'),
    ('00000000-0000-0000-0000-00000000000b'),
    ('00000000-0000-0000-0000-00000000000c');

create function pg_temp.login(uid text) returns void language sql as $$
    select set_config('request.jwt.claim.sub', uid, false);
$$;
create function pg_temp.check(ok boolean, what text) returns void language plpgsql as $$
begin
    if not ok then raise exception 'FEJL: %', what; end if;
    raise notice 'ok: %', what;
end $$;
create function pg_temp.expect_error(stmt text, expected text) returns void language plpgsql as $$
begin
    execute stmt;
    raise exception 'FEJL: forventede fejl "%" fra: %', expected, stmt;
exception when others then
    if sqlerrm like 'FEJL:%' then raise; end if;
    if position(expected in sqlerrm) = 0 then
        raise exception 'FEJL: forventede "%", fik "%"', expected, sqlerrm;
    end if;
    raise notice 'ok: afvist (%)', expected;
end $$;
grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.check((select count(*) = 3 from public.profiles), 'profil oprettes automatisk for nye brugere');
select pg_temp.check((select bool_and(friend_code ~ '^[A-HJ-NP-Z2-9]{6}$') from public.profiles), 'vennekoder har gyldigt format');

select set_config('test.code_b', (select friend_code from public.profiles where id = '00000000-0000-0000-0000-00000000000b'), false);

set role authenticated;

-- Bruger A
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select pg_temp.check((select count(*) = 1 from public.profiles), 'RLS: A kan kun se sin egen profil');
select pg_temp.check((select display_name = 'Ny kører' from public.my_profile()), 'my_profile virker');
select pg_temp.expect_error($$update public.profiles set trophies = 999$$, 'permission denied');
select pg_temp.expect_error($$insert into public.friendships values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000c')$$, 'permission denied');

select * from public.update_profile('Anna', 'Golf', true) \g /dev/null
select public.update_status(12.5, 2, 35, true, 55.23, 11.76);
select pg_temp.check((select display_name = 'Anna' and explored_km2 = 12.5 and last_lat = 55.23 from public.my_profile()), 'A opdaterer profil og status');

select pg_temp.expect_error($$select public.add_friend('ZZZZZZ')$$, 'invalid_code');
select pg_temp.expect_error(format($$select public.add_friend(%L)$$, (select friend_code from public.my_profile())), 'own_code');

select pg_temp.check((select display_name = 'Ny kører' from public.add_friend(lower(current_setting('test.code_b')))), 'A tilføjer B med kode (små bogstaver er ok)');
select pg_temp.expect_error(format($$select public.add_friend(%L)$$, current_setting('test.code_b')), 'already_friends');
select pg_temp.check((select count(*) = 1 from public.get_friends()), 'A ser én ven');

-- Bruger B: venskabet er gensidigt
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select pg_temp.check((select display_name = 'Anna' and last_lat = 55.23 and is_driving from public.get_friends()), 'B ser A inkl. position');

-- A slår positionsdeling fra
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select * from public.update_profile('Anna', 'Golf', false) \g /dev/null
select public.update_status(13, 2, 35, true, 55.30, 11.80);
select pg_temp.check((select last_lat is null from public.my_profile()), 'position slettes når deling slås fra');

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select pg_temp.check((select last_lat is null and last_lon is null and not is_driving and explored_km2 = 13 from public.get_friends()), 'B ser A''s fremskridt men ikke position');

-- C er ikke ven med nogen
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select pg_temp.check((select count(*) = 0 from public.get_friends()), 'C ser ingen venner');

-- B fjerner A
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.remove_friend('00000000-0000-0000-0000-00000000000a');
select pg_temp.check((select count(*) = 0 from public.get_friends()), 'B har fjernet A');
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select pg_temp.check((select count(*) = 0 from public.get_friends()), 'venskabet er væk for A også');

-- Ikke logget ind
reset role;
set role anon;
select pg_temp.login('');
select pg_temp.expect_error($$select * from public.get_friends()$$, 'permission denied');
reset role;
\o
\echo 'ALLE TESTS BESTÅET'
