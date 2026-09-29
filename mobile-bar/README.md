# brewdiary bar: the venue staff app (Flutter, Android + iOS)

The app for the people who run a bar or restaurant: the floor and tables, orders, the bar and kitchen
screens, bills, guests at the table, stock, the rota and the manager's numbers. Access follows the
person's role (owner, manager, supervisor, bartender, server, host, kitchen).

It uses the **same Supabase backend** as the website and the guest app in [`test_m_app/`](../test_m_app/):
the same tables, row-level security, server functions and legal checks. The web dashboard at
bar.bwdy.site keeps working alongside it.

## Status

**Planning; no code yet.** [PLAN.md](PLAN.md) is the full list of what to build, module by module
(M0–M21), with the decisions that need the maintainer's call (section 4) and the problems found while
scanning the repo (section 1.4).

## How work lands here

- One module at a time, pushed when its checks pass.
- Database changes go in `supabase/` as new migrations (044 onward), with `scripts/db-audit.mjs` and
  `scripts/verify-flow.mjs` updated alongside. The maintainer runs migrations, then `npm run db:audit`
  and `npm run db:verify`.
- Logic shared with the guest app lives in one place (PLAN.md, decision D1), covered by parity tests.
- UI work uses the `taste-engine` skill; charts use `dataviz`.
- House rules from [`CLAUDE.md`](../CLAUDE.md) apply unchanged, above all: nothing rewards drinking
  more, a guest's diary never reaches a venue, and legality is enforced in the database.
