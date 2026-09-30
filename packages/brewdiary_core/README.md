# brewdiary_core

brewdiary's pure logic in Dart: day keys and dates, the diary derivations (streaks, the mosaic,
milestones), drink matching, money formatting (`₹1,23,456`), the jurisdiction mirror, menus and
handles. No Flutter, no network, no database.

It is a 1:1 port of the website's `src/lib`, and its tests are ported from the website's vitest
suite, so both behave identically. **Change one, change both.**

Used by the guest app ([`test_m_app/`](../../test_m_app/)) and the venue app
([`mobile-bar/`](../../mobile-bar/)) through a path dependency:

```yaml
dependencies:
  brewdiary_core:
    path: ../packages/brewdiary_core
```

```bash
cd packages/brewdiary_core
dart pub get
dart analyze
dart test
```
