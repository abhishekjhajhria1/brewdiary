-- ============================================================================
-- brewdiary — currency. "₹" was hardcoded into eight components, which is fine
-- right up until a bar in London sets a perk and the app tells its guests to
-- spend "₹3000". Currency is a property of the PLACE, not of the app.
--
-- A venue carries its own currency, DERIVED FROM ITS COUNTRY and set by the
-- server — the dashboard never gets to claim one, so a venue's tab and its perk
-- can never disagree about what the money means.
-- Runs on top of schema.sql + 002..021. Idempotent-ish.
-- ============================================================================

alter table public.venues      add column if not exists currency text not null default 'INR';
alter table public.venue_perks add column if not exists currency text not null default 'INR';
alter table public.venues      drop constraint if exists venues_currency_check;
alter table public.venues      add constraint venues_currency_check check (currency ~ '^[A-Z]{3}$');

-- ISO-4217 for every country in jurisdiction_policy. One place, so the app and the
-- database can never drift on what a bar's money is.
create or replace function public.currency_for_country(c text)
returns text language sql immutable set search_path = public as $$
  select case upper(coalesce(c, ''))
    when 'IN' then 'INR' when 'US' then 'USD' when 'GB' then 'GBP'
    when 'IE' then 'EUR' when 'FR' then 'EUR' when 'DE' then 'EUR'
    when 'ES' then 'EUR' when 'IT' then 'EUR' when 'NL' then 'EUR'
    when 'FI' then 'EUR' when 'AU' then 'AUD' when 'CA' then 'CAD'
    when 'NZ' then 'NZD' when 'SG' then 'SGD' when 'JP' then 'JPY'
    when 'KR' then 'KRW' when 'TH' then 'THB' when 'NO' then 'NOK'
    when 'SE' then 'SEK' when 'PL' then 'PLN' when 'TR' then 'TRY'
    when 'ZA' then 'ZAR' when 'BR' then 'BRL' when 'MX' then 'MXN'
    when 'AE' then 'AED' else 'INR' end;
$$;
grant execute on function public.currency_for_country(text) to anon, authenticated;

-- The venue's currency follows its country. SERVER-SET: whatever the client sends
-- is overwritten, so a dashboard cannot mislabel a bar's money.
create or replace function public.venues_set_currency()
returns trigger language plpgsql set search_path = public as $$
begin
  new.currency := public.currency_for_country(new.country);
  return new;
end; $$;

drop trigger if exists venues_currency on public.venues;
create trigger venues_currency before insert or update of country on public.venues
  for each row execute function public.venues_set_currency();

update public.venues set currency = public.currency_for_country(country);

-- A perk's currency follows its venue's, likewise server-set.
create or replace function public.venue_perks_set_currency()
returns trigger language plpgsql set search_path = public as $$
begin
  select v.currency into new.currency from public.venues v where v.id = new.venue_id;
  return new;
end; $$;

drop trigger if exists venue_perks_currency on public.venue_perks;
create trigger venue_perks_currency before insert or update on public.venue_perks
  for each row execute function public.venue_perks_set_currency();

update public.venue_perks p set currency = v.currency from public.venues v where v.id = p.venue_id;

-- The wall board's tab strip has to say which money it means.
drop function if exists public.room_tabs(text) cascade;
create or replace function public.room_tabs(code text)
returns table (display_name text, spend numeric, currency text)
language sql stable security definer set search_path = public as $$
  select coalesce(p.display_name, 'guest') as display_name,
         sum(se.amount)::numeric as spend,
         coalesce(v.currency, 'INR') as currency
  from public.parties party
  join public.room_consent rc on rc.party_id = party.id
                             and rc.on_board = true and rc.show_tab = true
  join public.spend_events se on se.party_id = party.id and se.subject_user_id = rc.user_id
  join public.profiles p on p.id = rc.user_id
  left join public.venues v on v.id = party.venue_id
  where party.invite_code = lower(trim(code))
    and public.board_live(party)
  group by p.id, p.display_name, v.currency
  order by 2 desc, 1;
$$;
revoke all on function public.room_tabs(text) from public;
grant execute on function public.room_tabs(text) to anon, authenticated;
