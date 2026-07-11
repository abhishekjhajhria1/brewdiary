-- ============================================================================
-- brewdiary — 007: PARTY JOIN REQUESTS (host approval).
-- Runs on top of 004_parties.sql. Turns any invite link into a safe "open party":
-- share it as widely as you like, but whoever clicks it lands as a PENDING request
-- and the HOST approves (or declines) each person — their profile is visible to the
-- host so they can decide. Sharing into / reading the shared party log requires an
-- APPROVED membership, so pending requesters can't see the night until they're let in.
-- Idempotent-ish.
-- ============================================================================

-- member status: existing rows + the host default to 'approved'; new joiners = 'pending'
alter table public.party_members
  add column if not exists status text not null default 'approved'
  check (status in ('pending', 'approved'));

-- approved-only membership — used to gate sharing + reading the shared log
create or replace function public.is_approved_party_member(pid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.party_members m
    where m.party_id = pid and m.user_id = uid and m.status = 'approved'
  );
$$;

-- a shared entry is visible only to APPROVED members of a party it's shared into
create or replace function public.entry_in_my_party(eid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.party_shares s
    join public.party_members m on m.party_id = s.party_id
    where s.entry_id = eid and m.user_id = uid and m.status = 'approved'
  );
$$;

-- joining by code/link now creates a PENDING request (the host is auto-approved).
-- Returns the caller's current status so the UI can say "request sent" vs "you're in".
drop function if exists public.join_party(text) cascade;
create or replace function public.join_party(code text)
returns table (id uuid, name text, status text)
language plpgsql security definer set search_path = public as $$
declare p public.parties; cur text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into p from public.parties where invite_code = lower(trim(code));
  if p.id is null then raise exception 'invalid code'; end if;
  select m.status into cur from public.party_members m
    where m.party_id = p.id and m.user_id = auth.uid();
  if cur is null then
    cur := case when p.host_id = auth.uid() then 'approved' else 'pending' end;
    insert into public.party_members (party_id, user_id, status) values (p.id, auth.uid(), cur);
  end if;
  return query select p.id, p.name, cur;
end; $$;
revoke all on function public.join_party(text) from public;
grant execute on function public.join_party(text) to authenticated;

-- the host approves a pending member (definer: verifies the caller hosts the party)
create or replace function public.approve_party_member(pid uuid, uid uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.parties p where p.id = pid and p.host_id = auth.uid()) then
    raise exception 'not the host';
  end if;
  update public.party_members set status = 'approved' where party_id = pid and user_id = uid;
end; $$;
revoke all on function public.approve_party_member(uuid, uuid) from public;
grant execute on function public.approve_party_member(uuid, uuid) to authenticated;
-- (declining a request = the host deletes the member row, already allowed by
--  party_members_delete's host clause in 004.)

-- public invite preview counts only APPROVED 'going'
create or replace function public.party_preview(code text)
returns table (name text, date date, venue text, host_name text, going int)
language sql stable security definer set search_path = public as $$
  select p.name, p.date, p.venue,
         coalesce(h.display_name, 'someone') as host_name,
         (select count(*)::int from public.party_members m
           where m.party_id = p.id and m.status = 'approved' and m.rsvp = 'going') as going
  from public.parties p
  left join public.profiles h on h.id = p.host_id
  where p.invite_code = lower(trim(code));
$$;
revoke all on function public.party_preview(text) from public;
grant execute on function public.party_preview(text) to anon, authenticated;

-- the shared party log is APPROVED-members-only (pending requesters can't peek)
drop policy if exists party_shares_read on public.party_shares;
create policy party_shares_read on public.party_shares for select to authenticated
  using (public.is_approved_party_member(party_id, auth.uid()));

drop policy if exists party_shares_insert on public.party_shares;
create policy party_shares_insert on public.party_shares for insert to authenticated
  with check (user_id = auth.uid()
          and public.is_approved_party_member(party_id, auth.uid())
          and exists (select 1 from public.entries e where e.id = entry_id and e.user_id = auth.uid()));
