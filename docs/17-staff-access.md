# 17 — The team: adding employees, the owner's code, pausing access, hours

This chapter is about running a venue's team in the venue app (`mobile-bar/`) and on the venue
dashboard (bar.bwdy.site). An owner adds an employee and picks their role. The employee signs in with
their own email and types a code the owner gave them. An owner or manager can pause anyone's access at
any moment and tell them who to report to. It all runs on `supabase/053_staff_access.sql`.

1. [In one minute](#1-in-one-minute)
2. [Adding an employee: the owner's code](#2-adding-an-employee-the-owners-code)
3. [A shared invite code waits for a yes](#3-a-shared-invite-code-waits-for-a-yes)
4. [Pausing someone's access](#4-pausing-someones-access)
5. [Who may do what](#5-who-may-do-what)
6. [The team's history](#6-the-teams-history)
7. [The time clock](#7-the-time-clock)
8. [The rules the database enforces](#8-the-rules-the-database-enforces)
9. [Switching it on](#9-switching-it-on)
10. [Trying it in the demo](#10-trying-it-in-the-demo)
11. [Not built yet](#11-not-built-yet)
12. [Where it lives](#12-where-it-lives)

---

## 1. In one minute

- **The owner adds people.** Name, email, phone (optional) and a role. The app shows a 6-digit code
  once. The owner shares it (or says it out loud).
- **The employee joins in two steps.** First they sign in with their own email. brewdiary emails them a
  sign-in code, which proves the address is theirs. Then they type the owner's code, which proves the
  owner meant *them*. Only then are they on the team, with the role the owner chose.
- **Anyone can be paused.** An owner or manager pauses someone's access with a reason and the person to
  report to. Everything at that venue stops for them at once, and they see:
  *"Your access is paused. Please report to Arjun (manager)."*
- **Nothing is silent.** Every change to the team is written down: who joined, who approved them, who
  was paused and why, and who changed a role.

## 2. Adding an employee: the owner's code

```
 Owner (Team › Add an employee)            Employee (their own phone)
 ─────────────────────────────             ──────────────────────────
 Rahul S. · rahul@gmail.com · Server
 "Make their code"  →  482 913  (shown once)
 Share / tell them ──────────────────────► installs brewdiary bar
                                           signs in with rahul@gmail.com  ← factor 1: the emailed
                                                                            sign-in code
                                           Your venues › "A code to type":
                                             The Amber Room — added you as a server
                                           types 482913                   ← factor 2: the owner
                                           → on the team, as a server
 Team: Rahul is "On the team"
```

- The code works **only for the email the owner typed**. A code that leaks to someone else is useless
  to them.
- It lasts **48 hours**, allows **5 tries** and works **once**. A wrong try says how many are left.
  After 5 wrong tries, or once it runs out, the owner taps **New code**. A new code retires the old one.
- The code is **never stored**. The database keeps only a scrambled copy (a salted SHA-256 hash), and
  nobody can read even that: the table has no read rule at all.
- A new employee without a brewdiary account creates one at sign-in with the same email. The sign-in
  screen offers this when it sees the email is new.
- The owner's list shows who is **added, not in yet**, when their code runs out, and whether they've
  used up their tries.

## 3. A shared invite code waits for a yes

The older 10-letter invite code (for a group chat or a notice board) still works, but it **no longer
puts anyone straight on the team**. A code can travel further than meant. The person appears under
**Waiting for your yes**. An owner or manager taps them, sees their @handle and how they asked, and says
**Approve** or **Say no**. Until then they have no powers at all.

Adding someone by searching their @handle has gone. The database refuses it: pick the wrong handle and
a stranger could have been working your floor without agreeing to anything.

## 4. Pausing someone's access

From **Team**, tap a person, then **Pause their access**. Add why (they'll see it, up to 200 letters)
and who they should report to: any owner or manager who is working there now.

What happens:

- **In the database, at once.** Every permission check asks "are they *active* staff here?", so every
  screen, table and function stops for them in the same moment. There is no list of places to remember.
- **On their phone, within a minute.** The venue app re-checks every minute while it's open, whenever
  it comes back to the front, and straight after the database refuses anything. They then see the
  paused screen: the venue, who to report to, the reason, and when. The venue's screens close.
- **They're clocked out**, and they can't clock back in.
- **Nothing they recorded is lost.** Tabs, notes and history stay.
- **Given access again** (the person's menu, **Give access again**), they go straight back in. To
  change the message without unpausing, use **Change the message**.

Nobody can pause themself, nobody can pause the owner, and a manager can't pause another manager.

## 5. Who may do what

| Action | Owner | Manager | Everyone else |
| --- | --- | --- | --- |
| Add an employee, new code, cancel a code | any role but owner | the floor roles (not a manager) | — |
| Approve or say no to someone who used a shared invite | yes | the floor roles | — |
| Pause and give access again | anyone but the owner | the floor roles | — |
| Change a role, remove someone | yes | the floor roles | leave the team themself |
| Their details (the name they go by, a phone number) | yes | the floor roles | their own |
| The team's history | the whole team | the whole team | their own |
| Hours | everyone's | everyone's | their own |
| Clock in and out | yes | yes | yes |
| Clock someone else out (they forgot) | yes | yes | — |

"The floor roles" are shift lead, bartender, server, host and kitchen. Ownership is never handed out
from an app; the person who created the venue is its owner.

Phone numbers are seen only by owners, managers and the person themself, never by the rest of the team.

## 6. The team's history

**Team › Team history** lists every change in plain sentences, newest first:

> You added Rahul S. as a server · today at 13:28
> Kabir asked to join as a server · today at 11:28
> You paused Leo's access: "Missed two shifts — come and see me" · 1 day ago
> Noor joined as a server with the owner's code · 6 days ago

A **trigger** in the database writes it (a trigger is a rule that runs on every change to the table).
So no path can skip it: not the app, not the website, not a server function. Owners and managers see
the venue's history; everyone can see their own.

## 7. The time clock

- **More › Your shift**: *Clock in* / *Clock out*, and how long you've been on.
- **Team › Hours**: who's on now, and everyone's time this week, over 14 days or over 30 days.
  Owners and managers see the team; everyone else sees themself.
- It is **for pay and fairness only**. The list is in **name order, never ranked by hours**, and it
  records *when*, never *where* or *what* anyone did. This follows the same rule as thanks from guests
  (doc 11): no league table of staff.
- A manager can clock out someone who forgot, and that is written to the history.

## 8. The rules the database enforces

These hold whichever app is used, because the database checks them, not the screen:

- A roster row can't be inserted by an app, except the creator's own "owner" row when they create the
  venue. The ways onto a team are the owner's code or an invite a manager approves.
- Only **active** staff count. `is_venue_staff`, `is_venue_manager` and `venue_role` ignore anyone
  waiting or paused, so a lock-out stops everything at once.
- A paused or waiting person can read **their own** roster row, to see why and who to see, and nothing
  else of the venue.
- The codes table has **no read or write rules at all**. Only its functions touch it, and they never
  return a code except once, to the person who made it.
- A wrong code is **counted, not undone**. The function returns an answer instead of an error, because
  an error would roll back the count with it.
- A paused person can't unpause themself with a fresh code.
- Nobody writes the history, the shifts or the details directly: functions and the trigger only.

`npm run db:audit` checks each of these on the real database. `npm run db:verify` plays them all
through as real users (about 60 steps). `npm run db:contract` checks that every call the apps make
fits the schema.

## 9. Switching it on

1. **Run the migration** on the real database: `node scripts/db.mjs supabase/053_staff_access.sql`
   (after 002–052). It is safe to run again. Everyone already on a team stays exactly as they were:
   active.
2. **Check it:** `npm run db:audit` and `npm run db:verify`.
3. **Install the new venue app** (the APK from GitHub Actions, built with the Supabase values; see
   `mobile-bar/README.md`). An app older than this migration still works: it keeps its old roster
   screens. A database older than the app shows a plain "apply migration 053" message instead of an
   error.
4. **Tell your team** the new way in: the owner adds them, and they type the owner's code.

## 10. Trying it in the demo

The demo venue (the app with no Supabase values) has the whole flow on the phone:

- **Your venues** shows *A code to type* for **Café Nilgiri**. The code is **482913**. Try a wrong one
  first.
- **The Tap House** is *paused*: tap it to see the paused screen.
- **The Amber Room › More › Team**: **Kabir** is waiting for your yes, **Rahul S.** is added but not in
  yet, **Leo** is paused, and Ira and Sam are on shift. Add an employee, pause Sam, look at **Hours** and
  **Team history**.

## 11. Not built yet

- **A new phone needs the owner again?** Not yet. The owner's code is asked for once, when someone
  joins. After that, signing in with their email on another phone is enough. A "new device waits for a
  manager's OK" step is designed but not built. It would need the app to identify each phone, and it
  changes the website's sign-in too.
- **Instant push of a pause.** Today the phone notices within a minute (sooner if they tap anything).
  A live push (Supabase Realtime on the roster) would make it instant.
- **Rotas** (planned shifts), **breaks**, and a **payroll export** of the hours.

## 12. Where it lives

| What | Where |
| --- | --- |
| The database: statuses, codes, approvals, pausing, history, shifts | `supabase/053_staff_access.sql` |
| Its checks | `scripts/db-audit.mjs` (staff access), `scripts/verify-flow.mjs` (scene 23), `scripts/check-app-contract.mjs` |
| The venue app: Team, add an employee, pausing, hours, history | `mobile-bar/lib/ui/screens/team_screen.dart`, `staff_hours_screen.dart`, `staff_history_screen.dart` |
| The venue app: typing the code, the paused screen, re-checking | `mobile-bar/lib/ui/screens/venues_screen.dart`, `locked_screen.dart`, `mobile-bar/lib/data/session.dart` |
| The words, twinned on both sides | `mobile-bar/lib/logic/staff.dart`, `src/lib/staffAccess.ts` |
| The dashboard's team tab and the codes to type | `src/components/venue/VenueApp.tsx`, `src/lib/venues.ts` |
