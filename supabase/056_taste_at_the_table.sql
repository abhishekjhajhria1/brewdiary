-- ============================================================================
-- brewdiary — your taste at the table (056).
--
-- The maintainer's call (1 Oct 2026): when a guest opens a venue's table link (tap
-- the NFC tag or scan the QR), the bartender gets their taste — so the drink they
-- make is one the guest will like — and the venue knows who's in tonight (so staff
-- can punch a card without searching everyone).
--
-- How it stays decent:
--   • THE GUEST SAYS YES ONCE. The app asks the first time ("share my taste when I
--     open a venue's menu"); after that it shares on its own, with a visible
--     "shared with <venue> tonight · stop" line. Off any time.
--   • TASTE, NOT A DIARY. What's shared is the taste card worked out on the phone
--     (what you're into, the kinds you usually have, the mood words, alcohol-free
--     often, "nothing with alcohol tonight", diet and allergies if you add them).
--     No entries, no dates, no counts, no places — never where else you've been.
--   • TONIGHT ONLY. A share lasts 8 hours, then it's gone from every staff screen.
--   • ONLY THE PEOPLE MAKING YOUR DRINK. Read through venue_can(…, 'guests.taste'):
--     owner, manager, supervisor, bartender, server. Not hosts, not the kitchen.
--   • PRESENCE IS NOT A VISIT. Opening a link never records a visit or a perk punch
--     — those stay staff-recorded (a guest can't write their own reward).
--
-- And the guest's card: a 6-letter code shown in the app, good for 10 minutes,
-- that staff type to find the guest at the till (instead of searching everyone).
-- ============================================================================

create table if not exists public.taste_shares (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  venue_id   uuid not null references public.venues(id) on delete cascade,
  table_id   uuid references public.venue_tables(id) on delete set null,
  taste      jsonb not null,
  shared_at  timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (user_id, venue_id)
);
create index if not exists taste_shares_venue_idx on public.taste_shares (venue_id, expires_at);
alter table public.taste_shares enable row level security;

-- The guest sees and stops their own; nobody writes a row directly.
drop policy if exists taste_shares_own_read on public.taste_shares;
create policy taste_shares_own_read on public.taste_shares for select to authenticated using (user_id = auth.uid());
drop policy if exists taste_shares_own_delete on public.taste_shares;
create policy taste_shares_own_delete on public.taste_shares for delete to authenticated using (user_id = auth.uid());

-- Only these keys, only these shapes, and small. Anything else is dropped.
create or replace function public.clean_taste(t jsonb)
returns jsonb language plpgsql immutable as $$
declare
  out jsonb := '{}'::jsonb;
  k text;
  arr jsonb;
begin
  if t is null or jsonb_typeof(t) <> 'object' then return out; end if;
  foreach k in array array['into', 'usually', 'moods', 'diet', 'allergies'] loop
    if jsonb_typeof(t -> k) = 'array' then
      select coalesce(jsonb_agg(left(trim(x #>> '{}'), 40)), '[]'::jsonb) into arr
        from (select x from jsonb_array_elements(t -> k) x where jsonb_typeof(x) = 'string' limit 8) s;
      out := out || jsonb_build_object(k, arr);
    end if;
  end loop;
  foreach k in array array['alcohol_free_often', 'dry_tonight'] loop
    if jsonb_typeof(t -> k) = 'boolean' then out := out || jsonb_build_object(k, t -> k); end if;
  end loop;
  return out;
end $$;

-- The guest's phone calls this when they open bwdy.site/t/<code>.
create or replace function public.share_taste(in_code text, in_taste jsonb)
returns table (venue_name text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  t public.venue_tables;
  v public.venues;
  until timestamptz := now() + interval '8 hours';
begin
  if auth.uid() is null then raise exception 'sign in to share your taste' using errcode = '28000'; end if;
  if octet_length(coalesce(in_taste, '{}'::jsonb)::text) > 4096 then raise exception 'that''s too much to share'; end if;
  select * into t from public.venue_tables where code = lower(trim(in_code)) and active;
  select * into v from public.venues where id = t.venue_id;
  if t.id is null or not coalesce(v.verified, false) then raise exception 'no table with that code'; end if;
  insert into public.taste_shares (user_id, venue_id, table_id, taste, shared_at, expires_at)
       values (auth.uid(), v.id, t.id, public.clean_taste(in_taste), now(), until)
  on conflict (user_id, venue_id) do update
     set table_id = excluded.table_id, taste = excluded.taste, shared_at = now(), expires_at = until;
  return query select v.name, until;
end $$;
revoke all on function public.share_taste(text, jsonb) from public;
grant execute on function public.share_taste(text, jsonb) to authenticated;

create or replace function public.stop_taste_share(vid uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.taste_shares where user_id = auth.uid() and venue_id = vid;
$$;
revoke all on function public.stop_taste_share(uuid) from public;
grant execute on function public.stop_taste_share(uuid) to authenticated;

-- My live shares, for the "shared with <venue> tonight · stop" line.
create or replace function public.my_taste_shares()
returns table (venue_id uuid, venue_name text, table_label text, expires_at timestamptz)
language sql stable security definer set search_path = public as $$
  select s.venue_id, v.name, t.label, s.expires_at
    from public.taste_shares s
    join public.venues v on v.id = s.venue_id
    left join public.venue_tables t on t.id = s.table_id
   where s.user_id = auth.uid() and s.expires_at > now()
   order by s.shared_at desc;
$$;
revoke all on function public.my_taste_shares() from public;
grant execute on function public.my_taste_shares() to authenticated;

-- Staff: who's in tonight and what they like. The people who make the drinks.
create or replace function public.venue_guests_tonight(vid uuid)
returns table (user_id uuid, name text, handle text, table_label text, taste jsonb, shared_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.venue_can(vid, auth.uid(), 'guests.taste') then
    raise exception 'your role here can''t see guests'' taste' using errcode = '42501';
  end if;
  return query
    select s.user_id, p.display_name, p.handle, t.label, s.taste, s.shared_at
      from public.taste_shares s
      join public.profiles p on p.id = s.user_id
      left join public.venue_tables t on t.id = s.table_id
     where s.venue_id = vid and s.expires_at > now()
     order by t.label nulls last, s.shared_at;
end $$;
revoke all on function public.venue_guests_tonight(uuid) from public;
grant execute on function public.venue_guests_tonight(uuid) to authenticated;

-- ── the guest's card: a short code staff type at the till ───────────────────
create table if not exists public.guest_codes (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  code       text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  expires_at timestamptz not null
);
alter table public.guest_codes enable row level security;
-- no client policies: my_guest_code() and venue_find_guest() are the only doors

create or replace function public.my_guest_code()
returns table (code text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- no I, O, 0, 1
  c text;
  tries int := 0;
begin
  if auth.uid() is null then raise exception 'sign in first' using errcode = '28000'; end if;
  loop
    c := '';
    for i in 1..6 loop
      c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    begin
      insert into public.guest_codes (user_id, code, expires_at) values (auth.uid(), c, now() + interval '10 minutes')
      on conflict (user_id) do update set code = excluded.code, expires_at = excluded.expires_at;
      exit;
    exception when unique_violation then
      tries := tries + 1;
      if tries > 5 then raise; end if;
    end;
  end loop;
  return query select g.code, g.expires_at from public.guest_codes g where g.user_id = auth.uid();
end $$;
revoke all on function public.my_guest_code() from public;
grant execute on function public.my_guest_code() to authenticated;

-- Staff who can punch a card find the guest by the code they show. Nothing else
-- about the person comes back.
create or replace function public.venue_find_guest(vid uuid, in_code text)
returns table (user_id uuid, name text, handle text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.venue_can(vid, auth.uid(), 'perks.redeem') then
    raise exception 'your role here can''t look up guests' using errcode = '42501';
  end if;
  return query
    select p.id, p.display_name, p.handle
      from public.guest_codes g join public.profiles p on p.id = g.user_id
     where g.code = upper(trim(in_code)) and g.expires_at > now();
end $$;
revoke all on function public.venue_find_guest(uuid, text) from public;
grant execute on function public.venue_find_guest(uuid, text) to authenticated;
