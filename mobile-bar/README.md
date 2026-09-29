# brewdiary bar: the venue staff app (Flutter; iOS + Android, phones + tablets)

The app for the people who run a bar, club, restaurant, café, liquor store, sweet shop, bakery or any
shop: tonight's room or the till, the guests, the menu or shelf, the loyalty card, the numbers, the
area, the team and Ninkasi. What each person sees follows their role (owner, manager, supervisor,
bartender, server, host, kitchen); the database decides, the app only hides what the role can't use.

It uses the **same Supabase backend** as the website and the guest app in [`test_m_app/`](../test_m_app/):
the same tables, row-level security, server functions and legal checks. Logic shared with the guest
app lives in [`packages/brewdiary_core`](../packages/brewdiary_core/). The web dashboard at
bar.bwdy.site keeps working alongside it; a change in one shows in the other.

## Status

**R1 built** (PLAN.md M0–M2, plus every kind of shop): sign in, create or join a venue, roles and
invites, tonight's room or the till, guests and the guest book, the menu with 86 toggles and table-tag
QRs, the loyalty card, the numbers, area trends, the Ninkasi advisor, setup and verification.
[PLAN.md](PLAN.md) is the full list, module by module, with what's done and what's next.

Onboarding a venue is three steps: sign in with an emailed code, name + kind + country, done.
Everything else (location, verification, perks, menu, team) is optional and comes later.

## Run it

```bash
cd mobile-bar
flutter pub get
flutter run                                   # no env: a clearly labelled DEMO venue, no network
flutter run --dart-define-from-file=env.json  # the real backend (copy env.example.json → env.json)
```

`env.json` holds the Supabase URL, the **anon** key and `SITE_URL` (the website, for Ninkasi). Never a
service-role key; it's git-ignored. Phones stay portrait; tablets rotate.

## The database it needs

Migrations `044`–`047` in [`supabase/`](../supabase/) (guest-card fix, staff roles, capability gates,
every kind of shop). The maintainer runs them (`node scripts/db.mjs <file>`), then `npm run db:audit`
and `npm run db:verify`. Before that, `npm run db:local` applies every migration to a throwaway
Postgres and runs both checks against it.

## Test it

```bash
flutter analyze
flutter test        # logic (role parity with supabase/045, kinds, perk rules, insights) + walk-throughs
```

CI runs both on every push, next to the guest app and the core package.

## How work lands here

- One module at a time, pushed when its checks pass.
- Database changes go in `supabase/` as new migrations (048 onward), with `scripts/db-audit.mjs` and
  `scripts/verify-flow.mjs` updated alongside and proven with `npm run db:local`.
- Role capabilities exist three times on purpose: `supabase/045` (the authority),
  `src/lib/roles.ts` and `lib/logic/roles.dart`. Tests on both sides parse the SQL, so they can't drift.
- UI work uses the `taste-engine` skill; charts use `dataviz`. Every screen has to work on a phone and
  a tablet, iOS and Android.
- House rules from [`CLAUDE.md`](../CLAUDE.md) apply unchanged, above all: nothing rewards drinking
  more, a guest's diary never reaches a venue, and legality is enforced in the database.
