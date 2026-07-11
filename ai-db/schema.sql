-- ============================================================================
-- NINKASI DATA PLANE — the SEPARATE AI database (its own Supabase project).
--
-- This is NOT the app database. It is a second, dedicated Postgres whose ONLY job
-- is to hold the AI's data: the consented training corpus and anonymized trend
-- snapshots. It is reached ONLY from our server (never the browser), using a
-- service key kept in AI_SUPABASE_SERVICE_KEY. The browser has no credentials here.
--
-- WHY separate: a different security blast-radius from user data, isolation from the
-- live app's performance, and a clean home for future AI retrieval (RAG). The pipeline
-- that fills it is CONTROLLED and MINIMIZED — it never mirrors raw user data:
--   • exchanges carry a PSEUDONYMOUS user_ref (a salted hash), never the real user id,
--     never names/emails/photos. You can tell two rows are the same person (for dedup
--     and per-user delete) but you cannot identify who without the server-side salt.
--   • only CONSENTED exchanges are written (the "Help train Ninkasi" switch), and only
--     LIVE (teacher) replies — scripted fallbacks are never sent here.
--   • trend_snapshots hold only k-anonymous AGGREGATES (≥3 users), counts only.
--
-- Apply this in the SECOND Supabase project's SQL editor (or:
--   node scripts/db.mjs ai-db/schema.sql   with AI_SUPABASE_DB_URL set).
-- ============================================================================

-- ── the training corpus ──────────────────────────────────────────────────────
create table if not exists public.exchanges (
  id         uuid primary key default gen_random_uuid(),
  user_ref   text not null,                 -- salted hash of the app user id (pseudonymous)
  prompt     text not null,                 -- the guest's message
  reply      text not null,                 -- Ninkasi's (teacher) reply
  context    text,                          -- the personalization block in effect (for faithful replay)
  model      text,                          -- which teacher answered (provenance)
  created_at timestamptz not null default now()
);
create index if not exists exchanges_user_ref_idx on public.exchanges (user_ref);
create index if not exists exchanges_created_idx  on public.exchanges (created_at);

-- ── anonymized trend snapshots (optional; filled by a batch job from the app DB) ─
create table if not exists public.trend_snapshots (
  id          uuid primary key default gen_random_uuid(),
  captured_at timestamptz not null default now(),
  days_back   int  not null,
  kind        text not null,                -- 'drink' | 'mood'
  name        text not null,
  users       int  not null,                -- always ≥ 3 (k-anonymous)
  logs        int  not null
);
create index if not exists trend_snapshots_captured_idx on public.trend_snapshots (captured_at);

-- ── lock it down ─────────────────────────────────────────────────────────────
-- We connect with the SERVICE key (bypasses RLS) from the server only. Turning RLS
-- on with NO policies means the anon/public PostgREST role can read/write NOTHING —
-- so even if this project's anon key leaked, the corpus stays sealed. Belt and braces.
alter table public.exchanges       enable row level security;
alter table public.trend_snapshots enable row level security;
-- (no policies on purpose → deny-all for anon/authenticated; service_role still works)

revoke all on public.exchanges       from anon, authenticated;
revoke all on public.trend_snapshots from anon, authenticated;
