-- ============================================================================
-- brewdiary — "Split" (Splitwise-style shared drink tabs among friends).
-- Incremental migration — safe to run on top of schema.sql. Idempotent-ish:
-- drops its own objects first, then recreates.
--
-- Model: an EXPENSE has a payer + a total; EXPENSE_SHARES say who owes what
-- (split evenly by default). SETTLEMENTS record paybacks. A pair's balance is
-- derived: (what they owe me) − (what I owe them) − net settlements.
-- Everyone involved in an expense can see it (RLS). Only the creator edits it.
-- ============================================================================

drop table if exists public.settlements    cascade;
drop table if exists public.expense_shares cascade;
drop table if exists public.expenses       cascade;
drop function if exists public.can_see_expense(uuid, uuid) cascade;

create table public.expenses (
  id          uuid primary key default gen_random_uuid(),
  created_by  uuid not null references public.profiles(id) on delete cascade,
  payer_id    uuid not null references public.profiles(id) on delete cascade,
  description text not null,
  amount      numeric(12,2) not null check (amount > 0),
  created_at  timestamptz not null default now()
);
create index expenses_payer_idx   on public.expenses (payer_id);
create index expenses_creator_idx on public.expenses (created_by);

create table public.expense_shares (
  id         uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  amount     numeric(12,2) not null check (amount >= 0),
  unique (expense_id, user_id)
);
create index expense_shares_user_idx on public.expense_shares (user_id);

create table public.settlements (
  id         uuid primary key default gen_random_uuid(),
  from_id    uuid not null references public.profiles(id) on delete cascade,  -- who pays back
  to_id      uuid not null references public.profiles(id) on delete cascade,  -- who receives
  amount     numeric(12,2) not null check (amount > 0),
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (from_id <> to_id)
);
create index settlements_from_idx on public.settlements (from_id);
create index settlements_to_idx   on public.settlements (to_id);

-- SECURITY DEFINER so expense/share RLS can check membership without recursion.
create or replace function public.can_see_expense(eid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.expenses e where e.id = eid and (e.payer_id = uid or e.created_by = uid))
      or exists (select 1 from public.expense_shares s where s.expense_id = eid and s.user_id = uid);
$$;

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.expenses       enable row level security;
alter table public.expense_shares enable row level security;
alter table public.settlements    enable row level security;

-- expenses: everyone involved can read; only the creator writes/removes
create policy expenses_read on public.expenses for select to authenticated
  using (public.can_see_expense(id, auth.uid()));
create policy expenses_insert on public.expenses for insert to authenticated
  with check (created_by = auth.uid());
create policy expenses_delete on public.expenses for delete to authenticated
  using (created_by = auth.uid());

-- shares: readable by anyone who can see the parent expense; written by the expense creator
create policy shares_read on public.expense_shares for select to authenticated
  using (public.can_see_expense(expense_id, auth.uid()));
create policy shares_insert on public.expense_shares for insert to authenticated
  with check (exists (select 1 from public.expenses e where e.id = expense_id and e.created_by = auth.uid()));
create policy shares_delete on public.expense_shares for delete to authenticated
  using (exists (select 1 from public.expenses e where e.id = expense_id and e.created_by = auth.uid()));

-- settlements: visible to both parties; you can only record one you're part of
create policy settlements_read on public.settlements for select to authenticated
  using (from_id = auth.uid() or to_id = auth.uid());
create policy settlements_insert on public.settlements for insert to authenticated
  with check (created_by = auth.uid() and (from_id = auth.uid() or to_id = auth.uid()));
create policy settlements_delete on public.settlements for delete to authenticated
  using (created_by = auth.uid());
