# Changes to the users app

What changed in `test_m_app/`, newest first, and the goal behind each change. The plan for what comes
next is [`IMPROVEMENTS.md`](IMPROVEMENTS.md).

## 30 September 2026 — the review, written down (no code changes)

**Goal:** agree what to fix before changing anything.

- Added [`IMPROVEMENTS.md`](IMPROVEMENTS.md): 17 changes, most important first — never losing a diary
  offline, private photos that stay private, consent that's off by default, iPhone parity, tests.

## 29 September 2026 — on branch `claude/modest-wozniak-j9o3nw`

These came in while the venue app (`mobile-bar/`) was being built. Each is listed so you can keep or
revert it on its own.

### The table's own link — `6349c76`
**Goal:** a guest at a table can see the menu with the table known, and — only if the venue switches
it on — send an order request or call staff. Staff never see who asked.
- New `lib/data/table_order.dart`; `TableMenuScreen` in `lib/ui/screens/menu_screen.dart`; the
  `/t/<code>` route in `lib/app.dart`; `/t/` links claimed in `AndroidManifest.xml`.
- Menus show the veg / non-veg / egg / vegan mark and allergens.
- Fixed a crash when a sheet with a focused text box closed (`showBdSheet` now waits for the sheet's
  closing animation before returning).
- *Not asked for by the owner.* To remove it, revert the Dart and manifest parts of that commit; the
  crash fix in `lib/ui/widgets/common.dart` is worth keeping.

### The area map's consent switch — `3aac805`
**Goal:** the neighbourhood heat map (for venues) counts only people who said yes, twice.
- A "count my nights out" switch in Settings (`settings_screen.dart`), off by default, stored in
  `profiles.share_nights_out`.

### Shared logic with the venue app — `5784674`
**Goal:** one copy of the rules both apps depend on, so the two can't drift.
- The pure logic (dates, streaks, drinks, money, jurisdiction, menus) moved from `lib/core/` to
  `packages/brewdiary_core/`; the app's imports changed, its behaviour didn't. The parity tests moved
  with it.

### Reporting a person works — `6d2d6fc`
**Goal:** the safety report reaches moderators.
- It failed every time: an upsert is also checked against read policies, and `reports` has none by
  design. It's now a plain insert, and a duplicate is answered like a success, so dedup stays silent
  (`lib/data/safety.dart`).
