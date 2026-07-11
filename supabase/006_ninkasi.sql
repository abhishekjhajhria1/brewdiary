-- ============================================================================
-- brewdiary — Ninkasi 2.0 data layer: the training corpus + the curation engine.
-- Incremental migration — runs on top of schema.sql + 002..005. Idempotent-ish.
--
-- Two things live here:
--
-- 1. NINKASI_EXCHANGES — every consented chat exchange (prompt, reply, the
--    context block, which model answered). This is the distillation corpus:
--    a cheap teacher model (Groq etc.) answers users now; we accumulate its
--    answers centrally; later we fine-tune OUR OWN small model on this corpus
--    (scripts/ninkasi/) and point AI_BASE_URL at it. Consent: the client only
--    inserts when the user's "Help train Ninkasi" toggle is on; users can read
--    and delete their own rows. Only the service role (the training exporter)
--    reads the whole corpus.
--
-- 2. TASTE TRENDS — the responsible version of "learn from all users":
--    profiles.share_trends is OPT-IN (default false); taste_trends() returns
--    k-anonymous AGGREGATES ONLY (a drink/mood appears only when ≥3 distinct
--    consenting users logged it in the window). No user ids, no notes, no
--    photos, no per-person anything ever leaves the function.
-- ============================================================================

drop table if exists public.ninkasi_exchanges cascade;
drop function if exists public.taste_trends(int) cascade;

create table public.ninkasi_exchanges (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  prompt     text not null,
  reply      text not null,
  context    text,                                   -- the personalization block shown to the model
  model      text,                                   -- which teacher answered (or 'fallback')
  created_at timestamptz not null default now()
);
create index ninkasi_exchanges_user_idx on public.ninkasi_exchanges (user_id);

alter table public.ninkasi_exchanges enable row level security;

-- your chats are yours: write/read/delete your own. The training exporter uses
-- the service role, which bypasses RLS by design.
create policy ninkasi_own on public.ninkasi_exchanges for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── trends opt-in on the profile (default OFF — sharing is a choice) ─────────
alter table public.profiles
  add column if not exists share_trends boolean not null default false;

-- ── k-anonymous taste trends ─────────────────────────────────────────────────
-- days_back: how far to look (clamped 1..90). Returns top drinks and moods among
-- CONSENTING users only, each row backed by ≥3 distinct people. SECURITY DEFINER
-- because it aggregates over private entries — the k-threshold and count-only
-- shape are what make that safe.
create or replace function public.taste_trends(days_back int default 14)
returns table (kind text, name text, users int, logs int)
language sql stable security definer set search_path = public as $$
  with window_entries as (
    select e.user_id, e.drink, e.mood
    from public.entries e
    join public.profiles p on p.id = e.user_id
    where p.share_trends
      and e.date >= current_date - make_interval(days => greatest(1, least(days_back, 90)))::interval
  ),
  drinks as (
    select 'drink'::text as kind,
           min(drink) as name,
           count(distinct user_id)::int as users,
           count(*)::int as logs
    from window_entries
    group by lower(trim(drink))
    having count(distinct user_id) >= 3
  ),
  moods as (
    select 'mood'::text as kind,
           min(mood) as name,
           count(distinct user_id)::int as users,
           count(*)::int as logs
    from window_entries
    where mood is not null and trim(mood) <> ''
    group by lower(trim(mood))
    having count(distinct user_id) >= 3
  )
  select * from (
    (select * from drinks order by users desc, logs desc limit 8)
    union all
    (select * from moods order by users desc, logs desc limit 8)
  ) t;
$$;

revoke all on function public.taste_trends(int) from public;
grant execute on function public.taste_trends(int) to authenticated;
