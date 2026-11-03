-- CarXplore: profiler, venskaber og deling af fremskridt/position mellem venner.
--
-- Al adgang for appen går gennem RLS og et par RPC-funktioner:
--   my_profile()            -> min egen profil (inkl. vennekode)
--   update_profile(...)     -> skift visningsnavn, bil og om positionen deles
--   update_status(...)      -> send fremskridt + position (kaldes jævnligt)
--   add_friend(code)        -> bliv venner med ejeren af en vennekode
--   remove_friend(id)       -> fjern et venskab (begge veje)
--   get_friends()           -> mine venner med fremskridt (+ position hvis delt)

-- ---------------------------------------------------------------------------
-- Tabeller
-- ---------------------------------------------------------------------------

create table public.profiles (
    id             uuid primary key references auth.users (id) on delete cascade,
    display_name   text        not null default 'Ny kører'
                   check (char_length(display_name) between 1 and 40),
    car            text        not null default ''
                   check (char_length(car) <= 40),
    friend_code    text        not null unique
                   check (friend_code ~ '^[A-HJ-NP-Z2-9]{6}$'),
    explored_km2   double precision not null default 0 check (explored_km2 >= 0),
    trophies       integer     not null default 0 check (trophies >= 0),
    trophy_points  integer     not null default 0 check (trophy_points >= 0),
    share_location boolean     not null default true,
    is_driving     boolean     not null default false,
    last_lat       double precision check (last_lat between -90 and 90),
    last_lon       double precision check (last_lon between -180 and 180),
    last_seen      timestamptz,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now()
);

-- Et venskab gemmes i begge retninger, så opslag altid er "where user_id = mig".
create table public.friendships (
    user_id    uuid not null references public.profiles (id) on delete cascade,
    friend_id  uuid not null references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, friend_id),
    check (user_id <> friend_id)
);

create index friendships_friend_id_idx on public.friendships (friend_id);

-- ---------------------------------------------------------------------------
-- Row Level Security: man kan kun læse sin egen række direkte.
-- Venners data hentes via get_friends(), som styrer hvad der deles.
-- ---------------------------------------------------------------------------

alter table public.profiles    enable row level security;
alter table public.friendships enable row level security;

create policy "profiles: read own"
    on public.profiles for select to authenticated
    using (id = auth.uid());

create policy "friendships: read own"
    on public.friendships for select to authenticated
    using (user_id = auth.uid());

-- Ingen direkte skrivning; alt går gennem funktionerne nedenfor.
revoke insert, update, delete on public.profiles    from anon, authenticated;
revoke insert, update, delete on public.friendships from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Ny bruger -> profil med unik vennekode
-- ---------------------------------------------------------------------------

create function public.generate_friend_code()
returns text
language plpgsql
set search_path = ''
as $$
declare
    alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    code text;
begin
    loop
        code := '';
        for i in 1..6 loop
            code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
        end loop;
        exit when not exists (select 1 from public.profiles where friend_code = code);
    end loop;
    return code;
end;
$$;

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles (id, friend_code)
    values (new.id, public.generate_friend_code());
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- RPC-funktioner
-- ---------------------------------------------------------------------------

create function public.my_profile()
returns setof public.profiles
language sql
stable
security invoker
set search_path = ''
as $$
    select * from public.profiles where id = auth.uid();
$$;

create function public.update_profile(
    p_display_name   text,
    p_car            text,
    p_share_location boolean
)
returns setof public.profiles
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;

    return query
    update public.profiles
       set display_name   = coalesce(nullif(btrim(p_display_name), ''), display_name),
           car            = coalesce(btrim(p_car), car),
           share_location = coalesce(p_share_location, share_location),
           -- Slås deling fra, slettes den gemte position med det samme.
           last_lat       = case when p_share_location is false then null else last_lat end,
           last_lon       = case when p_share_location is false then null else last_lon end,
           updated_at     = now()
     where id = auth.uid()
    returning *;
end;
$$;

create function public.update_status(
    p_explored_km2  double precision,
    p_trophies      integer,
    p_trophy_points integer,
    p_is_driving    boolean,
    p_lat           double precision default null,
    p_lon           double precision default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;

    update public.profiles
       set explored_km2  = greatest(0, p_explored_km2),
           trophies      = greatest(0, p_trophies),
           trophy_points = greatest(0, p_trophy_points),
           is_driving    = p_is_driving,
           -- Position gemmes kun, hvis brugeren deler den.
           last_lat      = case when share_location and p_lat is not null then p_lat else last_lat end,
           last_lon      = case when share_location and p_lon is not null then p_lon else last_lon end,
           last_seen     = now(),
           updated_at    = now()
     where id = auth.uid();
end;
$$;

-- Det en ven må se om en anden. Positionen er null, hvis vennen ikke deler den.
create type public.friend_info as (
    id            uuid,
    display_name  text,
    car           text,
    explored_km2  double precision,
    trophies      integer,
    trophy_points integer,
    is_driving    boolean,
    last_lat      double precision,
    last_lon      double precision,
    last_seen     timestamptz
);

create function public.friend_info_of(p public.profiles)
returns public.friend_info
language sql
immutable
set search_path = ''
as $$
    select (
        p.id, p.display_name, p.car, p.explored_km2, p.trophies, p.trophy_points,
        p.is_driving and p.share_location,
        case when p.share_location then p.last_lat end,
        case when p.share_location then p.last_lon end,
        p.last_seen
    )::public.friend_info;
$$;

create function public.get_friends()
returns setof public.friend_info
language sql
stable
security definer
set search_path = ''
as $$
    select (public.friend_info_of(p)).*
      from public.friendships f
      join public.profiles p on p.id = f.friend_id
     where f.user_id = auth.uid()
     order by p.display_name;
$$;

create function public.add_friend(p_code text)
returns setof public.friend_info
language plpgsql
security definer
set search_path = ''
as $$
declare
    me     uuid := auth.uid();
    target public.profiles;
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;

    select * into target
      from public.profiles
     where friend_code = upper(btrim(p_code));

    if not found then
        raise exception 'invalid_code' using errcode = 'P0002';
    end if;
    if target.id = me then
        raise exception 'own_code' using errcode = '22023';
    end if;
    if exists (select 1 from public.friendships where user_id = me and friend_id = target.id) then
        raise exception 'already_friends' using errcode = '23505';
    end if;

    insert into public.friendships (user_id, friend_id)
    values (me, target.id), (target.id, me);

    return next public.friend_info_of(target);
end;
$$;

create function public.remove_friend(p_friend_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
    delete from public.friendships
     where (user_id = auth.uid() and friend_id = p_friend_id)
        or (user_id = p_friend_id and friend_id = auth.uid());
$$;

-- Kun indloggede brugere må kalde funktionerne.
revoke execute on all functions in schema public from public, anon;
grant execute on function
    public.my_profile(),
    public.update_profile(text, text, boolean),
    public.update_status(double precision, integer, integer, boolean, double precision, double precision),
    public.get_friends(),
    public.add_friend(text),
    public.remove_friend(uuid)
to authenticated;
