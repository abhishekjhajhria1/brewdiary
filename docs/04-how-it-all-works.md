# 04 — How it all works

Now we follow **real actions** through the code, start to finish. You don't need to read the code — just
follow the story. Each step names the file so you could go look if you wanted. (Words unclear? See the
[glossary](02-glossary.md).)

First, a mental model that covers almost everything:

```
   YOU tap something
        │
        ▼
   a COMPONENT (src/components/…)   ← the button/screen you touched
        │  calls
        ▼
   a LIB function or HOOK (src/lib/…)   ← the brain: "save this drink"
        │  talks to
        ▼
   the DATABASE (Supabase)   ← permanent storage, protected by RLS
        │  data comes back
        ▼
   derive.ts recalculates the streak/mosaic
        │
        ▼
   the screen updates automatically
```

That loop — **component → lib → database → recalculate → screen** — is the whole app, over and over.

---

## Story 1: Logging a drink (the core action)
1. You're on the **Calendar** (`components/calendar/CalendarHome.tsx`). You tap today's square
   (`DayCell.tsx`).
2. The **LogSheet** (`components/log/LogSheet.tsx`) slides up. You type "Negroni," pick the mood "cozy,"
   and tap **Log**.
3. LogSheet calls **`addEntry(...)`** from `src/lib/store.ts`, handing it your drink, mood, and today's
   date.
4. `store.ts` does two things at once:
   - **Optimistically** adds the entry to what's on screen *immediately*, so the square brightens with
     no wait. (If the save later fails, it quietly rolls back.)
   - In the background, saves the row to the **`entries` table** in Supabase. If you attached photos,
     they're uploaded to secure cloud **storage** and linked to the entry.
5. Because the list of entries changed, **`derive.ts`** recalculates your streak, the mosaic shading,
   and any milestone — and the calendar and streak counter refresh on their own.
6. Nothing about "streak = 5" was saved anywhere. It was *computed* from your entries. (That's the one
   rule from [doc 03](03-how-the-code-is-organized.md).)

**Private by default:** that entry is visible only to you. Sharing is a *separate* action (Story 4).

---

## Story 2: Signing up / logging in
1. A brand-new visitor lands on `app/page.tsx`, which shows the **Landing** page
   (`components/onboarding/Landing.tsx`) — with a *real, working* mini-calendar embedded.
2. They can log a first drink **without an account** (it's held in the browser's **localStorage** for
   now). This is the "try before you sign up" design.
3. When they choose to register, **`profile.ts`** calls Supabase **Auth** to create the account (email +
   password). Supabase sets a **session cookie** so they stay logged in.
4. **Migration moment:** `store.ts` notices they just signed in and **moves that first local drink up
   into the cloud database**, attaching it to the new account — so nothing they logged is lost.
5. On future visits, `app/page.tsx` (a **server** component) checks the session cookie *before the page
   even renders* and sends returning users straight to their calendar — they never see the landing page
   flash.
6. `src/middleware.ts` guards private screens (`/you`, `/together`, `/split`, `/bartender`, party
   pages): if you're not logged in, it redirects you home. Public pages stay open (`/`, `/discover`,
   public party invites `/p/...`).

---

## Story 3: The mosaic and the streak (how "derived" works)
There is **no "streak" or "mosaic" table** in the database. Instead:
1. `derive.ts` takes your list of entries.
2. For the **mosaic**, it counts how many drinks you logged on each day and picks a shade — more logs =
   brighter amber square. `DayCell.tsx` just paints whatever shade `derive.ts` says.
3. For the **streak**, it walks backward from today counting consecutive logged days. There's a **grace
   rule**: one missed night is forgiven, so a single slip doesn't wipe your streak.
4. For **milestones** (10, 50, 100 drinks…), it checks your total count.
5. Your **mood lexicon** (the words you've used, like "cozy," "celebratory") is just the unique moods
   pulled from your entries, most-used first.

All of it recalculates instantly whenever entries change. Delete an entry and everything corrects
itself, because it was never stored — only computed.

---

## Story 4: Sharing with friends (Together)
1. Every entry starts **private**. To share, you open an entry in the LogSheet and tap **Share**, then
   pick an audience: **Friends**, a **Circle**, or a **Party**.
2. Sharing to friends flips that entry's `visibility` to `"friends"` (`store.ts`). Sharing to a circle
   or party adds a link row in a junction table (`circle_shares` / `party_shares`) — the entry itself
   stays private; it's just *also* visible in that group.
3. On the **Together** screen (`components/together/Together.tsx`), the feed asks the database for
   "friends' entries marked friends-visible." Thanks to **RLS**, the database itself only returns entries
   you're actually allowed to see — the security is enforced at the data layer, not just in our code.
4. A **"cheers"** adds a row to the `reactions` table; a **comment** adds a row to `comments`. Both
   update live.
5. **Circles** (`Circles.tsx`) are private groups you join by an invite code. **Parties**
   (`Parties.tsx` / `PartyRoom.tsx`) are events with a shareable link that *even non-users* can open;
   as guests log drinks into the party, the party page grows into a **recap** (a drink grid, a photo
   wall, a mood cloud). **Challenges** are opt-in, and only ever inside a circle — never on your calm
   calendar.

The golden rule of Together: **the calendar stays a private, score-free diary; all the loud, social,
competitive stuff lives over here, and only if you opt in.**

---

## Story 5: Chatting with Ninkasi (the AI) — and the security guards
This one matters most for the AI work, so we go slow.

1. On the **Ninkasi** screen (`components/bartender/Bartender.tsx`) you type "something cozy" and hit
   **Ask**.
2. The component gathers a little **context** — your recent drinks and moods (from `derive.ts`), what
   friends have been pouring, anonymous trends — and sends your message + context to **our own
   back-end** at `/api/bartender` (`app/api/bartender/route.ts`).
3. **The back-end runs safety guards first** (`route.ts` + `lib/ratelimit.ts`):
   - **Rate limit:** at most ~20 chats per minute per person. Over that → it politely refuses (a "429").
     This stops anyone from spamming the AI and running up our bill.
   - **Size caps:** a giant message is rejected or trimmed, so nobody can inflate our token cost.
4. The back-end reads the **secret AI key** (`AI_API_KEY`) — which exists **only on the server**, never
   in the browser — and asks the AI provider (Groq, for now) to answer, wearing **Ninkasi's
   personality** (the system prompt from `lib/bartender.ts`).
5. The answer is **streamed** back word-by-word, so the chat types out live.
6. **If there's no key yet, or the provider errors,** the back-end falls back to charming **scripted
   replies** (also in `bartender.ts`) — so Ninkasi is never broken, just "pouring from memory."
7. **Consent + learning:** if the user left the **"Help train Ninkasi"** switch on (You → Settings),
   the finished exchange is saved to the `ninkasi_exchanges` table (`lib/training.ts`) — this is the
   raw material for training *our own* model later. Users can turn it off or delete their data anytime,
   and RLS means each person can only touch their own rows.

The key insight: **the browser never sees the AI key.** It only ever talks to *our* server, and our
server talks to the AI. That's the "secure path." Full detail in
[06 — Security & privacy](06-security-and-privacy.md).

---

## Story 6: Splitting a bar bill (Split)
1. On **Split** (`components/split/Split.tsx`) you add an expense: "Bar tab, ₹2,000, I paid, split
   between me + 3 friends."
2. `lib/expenses.ts` saves the expense and each person's share to the database.
3. It then **calculates balances** with pure math ("Priya owes you ₹500, you owe Sam ₹200"), nets
   everything out, and shows who owes whom. "Settle up" records a payment so balances zero out. Currency
   is ₹ (the app's author is in India).

---

## The recurring patterns you now recognize
- **Optimistic updates:** the screen changes instantly, the database catches up in the background.
- **Two modes:** logged-out = on-device (localStorage); logged-in = cloud (Supabase). Same functions,
  the data just lives in a different place — and your first local entry migrates up on sign-in.
- **RLS everywhere:** the database refuses to hand over data you're not allowed to see, no matter what
  the app code asks.
- **Derived, never stored:** streaks, mosaics, milestones, balances — all computed on the fly.

That's the whole app. Next: **[05 — The Ninkasi AI, explained](05-the-ninkasi-ai-explained.md)**.
