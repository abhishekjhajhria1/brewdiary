-- ============================================================================
-- brewdiary — "what did I actually spend?", for the person who spent it.
--
-- ── WHY THIS IS ALLOWED, WHEN THE VENUE-SIDE VERSION IS NOT ──────────────────
-- Rule #1 of this codebase is that nothing rewards drinking more. That rule
-- killed a per-guest spend view on the BAR's dashboard (051, prompt 3): a venue
-- that can rank its guests by money will work that list, and a guest who can see
-- they're second on it buys another round. Both halves of the harm need the same
-- ingredient — SOMEONE ELSE seeing your number, or you seeing it next to theirs.
--
-- Your own spending, shown only to you, has neither. It is the same shape as
-- goals.ts (weekly limits, dry days): a private mirror. If it changes behaviour
-- at all it changes it downward, which is the direction this product already
-- leans. Every bank app on earth does this and nobody calls it gambling.
--
-- So the line, stated precisely, is:
--   ✓ YOU see your own spend, across venues, over time.                (this file)
--   ✗ A VENUE sees a named guest's spend history.                      (refused)
--   ✗ ANYONE is ranked, scored, badged or rewarded by spend.           (refused)
--   ✗ Spend touches sparks, palate score, passport or any leaderboard. (refused)
--
-- That last one is the load-bearing one and it is enforced by ABSENCE: nothing
-- in points.ts, score.ts, expeditions.ts or derive.ts reads this function, and
-- nothing should ever be taught to. The game does not know money exists.
--
-- ── the two places a guest's money lives ────────────────────────────────────
-- 1. spend_events (017) — the older staff-typed tab TOTAL. One number, no lines.
--    Stored in MAJOR units (numeric 10,2) in the venue's currency.
-- 2. order_items (051) — real itemised lines, but only the ones a venue actually
--    attributed to this guest. Stored in MINOR units.
-- This function normalises both to MINOR units so the client never does currency
-- maths on a float. Currencies are carried per-row and NEVER summed together —
-- ₹ and $ do not add, and a "total" that pretends they do is a lie.
--
-- Runs on top of schema.sql + 002..051. Idempotent-ish.
--
-- ── DOWN-MIGRATION NOTES ────────────────────────────────────────────────────
--   drop function if exists public.my_spend_history(int) cascade;
--   drop function if exists public.minor_per_major(text) cascade;
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- 1. minor_per_major() — the mirror of money.ts's minorPerMajor.
--
-- Not always 100. ¥1000 is 1000 minor units, and dividing yen by 100 would tell
-- a guest in Tokyo they spent a hundredth of what they did.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.minor_per_major(c text)
returns int language sql immutable set search_path = public as $$
  select case upper(coalesce(c, '')) when 'JPY' then 1 when 'KRW' then 1 else 100 end;
$$;
grant execute on function public.minor_per_major(text) to anon, authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 2. my_spend_history() — the caller's own money, and ONLY the caller's own.
--
-- Note what this function does NOT take: a user id. There is no parameter by
-- which one person asks for another person's spending, so there is no argument a
-- venue's dashboard could pass to turn this into the surveillance view we
-- refused. `auth.uid()` is the whole of the scope, hardcoded, twice.
--
-- `settled` distinguishes a closed bill from a tab still running tonight, so the
-- UI can show a live table without pretending it's history.
-- ────────────────────────────────────────────────────────────────────────────
drop function if exists public.my_spend_history(int) cascade;

create or replace function public.my_spend_history(months int default 12)
returns table (
  source       text,      -- 'order' (itemised) | 'tab' (a staff-typed total)
  ref_id       uuid,
  on_date      date,
  venue_id     uuid,
  venue_name   text,
  currency     text,
  amount_minor bigint,
  items        int,       -- lines on an itemised order; null for a typed tab
  settled      boolean
)
language sql stable security definer set search_path = public as $$
  with win as (
    select (current_date - make_interval(months => greatest(coalesce(months, 12), 1)))::date as since
  )

  -- itemised: the lines a venue attributed to me, summed per order
  select
    'order'::text,
    o.id,
    (o.opened_at at time zone 'UTC')::date,
    v.id,
    v.name,
    o.currency,
    sum(oi.qty::bigint * oi.unit_price_minor::bigint),
    count(*)::int,
    o.status = 'closed'
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  join public.venues v on v.id = o.venue_id
  cross join win
  where auth.uid() is not null
    and oi.guest_user_id = auth.uid()
    and o.status <> 'void'
    and o.opened_at >= win.since
  group by o.id, v.id, v.name, o.currency, o.status

  union all

  -- typed tabs: one number the bar recorded against my name in a room
  select
    'tab'::text,
    se.id,
    coalesce(p.date, (se.created_at at time zone 'UTC')::date),
    v.id,
    v.name,
    coalesce(v.currency, 'INR'),
    round(se.amount * public.minor_per_major(coalesce(v.currency, 'INR')))::bigint,
    null::int,
    true
  from public.spend_events se
  join public.parties p on p.id = se.party_id
  left join public.venues v on v.id = p.venue_id
  cross join win
  where auth.uid() is not null
    and se.subject_user_id = auth.uid()
    and se.created_at >= win.since

  order by 3 desc, 5;
$$;
revoke all on function public.my_spend_history(int) from public;
grant execute on function public.my_spend_history(int) to authenticated;
