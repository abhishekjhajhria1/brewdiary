# brewdiary — the north star (the constitution)

This is the locked product + design spec, decided with the user on 2026-06-27 in a from-scratch
redesign. The user explicitly said: do NOT reuse or get inspired by any prior project, including the
old brewdiary (speakeasy dark theme, 3-theme switcher, "Ninkasi" AI bartender, Supabase scaffold).
Keep only the name. Everything below overrides any generic design recommendation.

## What it is
An **all-inclusive drink journal**. Not a sobriety tracker, not a connoisseur-only thing. You log any
drink — espresso, wine, beer, a cocktail you made, kombucha, a homebrew batch, a can. No forced
categories. You log whatever you want and share whatever you want.

## The ritual (the whole product in one sentence)
**The home IS a calendar. Tap a day → a tiny form slides in → log a drink. One tap, done.**
It is meant to be opened every night — a calm, must-do habit.

## The form (keep it tiny — ~5 fields)
1. What it was (free text / quick pick)
2. **Feeling = ONE-WORD MOOD** (decided). A single word for how the moment felt (cozy, celebratory,
   ordinary, comforting…). NOT a star/number rating — brewdiary is a diary, not a rating app. The field
   suggests a small tasteful starter set, allows free-typed words, and surfaces the user's OWN recurring
   words first so most nights it's one tap. Emoji-free, typographic. Consequence: moods accumulate into a
   personal **lexicon** ("cozy ×14") that becomes a collectible + a shelf filter. Everything stays
   count-based (no rating logic): streaks/milestones/mosaic all run on count, never on this word.
3. Optional note
4. Optional photo(s) (several, up to ~4)
5. ~~Share toggle~~ — REMOVED from the log moment (decided 2026-06-27). Logging is ALWAYS instant +
   private; there is no audience choice at log time. Sharing is a separate deliberate act afterward
   (tap an entry → share to friends / a circle / a party / export image). See "Sharing" below.

No walls of fields. If a field isn't one of these, justify it hard before adding it.

**Sheet behavior (locked 2026-06-27):** the log sheet slides up from the tapped day. Date at top set in
the editorial serif (reads as "a moment", not a form header). **Minimal-first disclosure:** the sheet
initially shows only *What did you drink?* (text + a quick-pick of the user's recent/common drinks so
repeat pours are one tap) + *Mood* (one-word, suggested chips + recurring words first + free-type) + the
*Log* button. A single quiet "add note · photo · place · who" row expands the optional fields on tap.
Time auto-captured (quietly editable). **Always private at log time — NO share control in the sheet.**
On submit, the day's square darkens **immediately (optimistic)**. True nightly path ≈ tap day → tap a
recent drink → tap a mood → done (2–3 taps).

**Sharing (decided 2026-06-27): "log private, share later."** Every entry is instant + private. Sharing
is a separate, deliberate gesture: tap an entry → **share to ▸ friends / a specific friend / a circle /
a party / export image**. This keeps logging frictionless and makes sharing intentional (diary-first,
social-second). External social share-out (the photo overlay) is its own explicit export action.
Contextual nicety: when logging from inside a party's shared-log, it may offer to add the entry to that
party — still the user's choice, default stays private otherwise.

## The collectible mechanic — streak mosaic, INTENSITY BY COUNT
- The calendar fills in over time and that filled grid is the reward.
- **Darker = more.** A day's square gets **darker/brighter the more times you logged that day.** Empty
  day = faint outline; one log = light fill; several logs = fuller fill. *(SUPERSEDED re: colour — since
  the 2026-06-30 glass pivot the fill GLOWS amber-by-count, not ink-monochrome. See "Design language v3"
  below. The count-driven intensity rule itself is permanent; only the hue changed.)*
- This is deliberately NOT color-coded-by-drink-type and NOT a single flat accent. The point is a quiet
  picture of *consistency / streaks* — that is the habit hook. You don't want to break the chain.
- The same mosaic is what you glance at on a friend's profile.

## Social — the second layer, never the front door
The calm personal calendar is what you open. From any entry you can push it to friends, see theirs,
react, and peek at their mosaics. Social is reachable but never the landing surface.

## Visual language — Swiss minimal
- Bone white (`#FFFFFF` / `#F7F6F3`-ish) + near-black text (`#111`, never pure `#000`). Muted grey for
  secondary (`#787774`-ish).
- **Type carries everything.** Fine hairline rules (`1px` light grey), small caps for labels, generous
  macro-whitespace, gallery-calm.
- Discipline over decoration. No heavy shadows, no pill-for-pill's-sake, no emoji icons.
  *(SUPERSEDED re: glass — since 2026-06-30 the user explicitly adopted a restrained **liquid-glass**
  surface system + a drink-hued ambient background + an amber-by-count mosaic. See "Design language v3".
  The discipline still holds: glass only on layered surfaces, text stays high-contrast, one accent, no
  AI-purple/neon. "Calm and not-slop" is the constant; "flat monochrome" was the old expression of it.)*
- Warmth and "playfulness" come from the mosaic + restrained micro-interactions, NOT from ornament.
- The explicit fear to design against: **"looks AI-generated."** Every slop tell (AI-purple, three equal
  cards, generic glass, Inter + slate-900, infinite micro-animations) is banned. See `anti-slop.md`.

## Feature set (locked 2026-06-27)
**Logging:** tap any day (today or backfill) → tiny form. Core 5 fields (what it was · feeling/mark ·
note · photo · share toggle) PLUS optional: where/venue · who-with · drink type/tag (for filtering the
shelf, NOT for coloring the mosaic) · time-of-day (auto). Multiple logs per day (mosaic intensity = count).
Edit/delete.
**Calendar:** month view (home) + full **year mosaic** (the big collectible picture) + tap-day → that
day's entries. Intensity-by-count, today emphasis.
**Shelf:** searchable/filterable history of everything logged + a quiet stat line ("47 drinks · 12 kinds").
Calm, never a dashboard.
**Social — a real "Together" layer (the Feed tab IS this hub), governing rule: the loud/communal/
competitive stuff lives HERE, the Calendar stays a calm pure diary with no scores ever:**
- **Feed:** friends' shared entries · one "cheers" reaction · comments · view a friend's mosaic.
- **Share card / photo overlay (Strava-style):** turn any entry into an overlay on the user's OWN photo →
  export → push to connected external socials. **Content (decided):** drink name (editorial serif) ·
  one-word mood · date (tabular) · a **streak / mini-mosaic sliver shown by default** · a discreet
  brewdiary mark (corner). Auto-contrast text + soft local scrim only behind the caption; photo is the hero.
- **Circles:** private groups (close friends, tasting club, roommates) — shared feed + **combined circle
  mosaic** + circle-only sharing.
- **Parties / events:** host an event (tasting, night out, homebrew share) → invite friends **in-app + a
  shareable link** (works for non-users too = growth) → RSVP → a **shared party log** (everyone logs into
  one collection → the party gets its own mini-mosaic + photo wall) → a **party recap** group-memory page.
  Optional "happening now" live view. **Recap content (decided):** header (party name serif · date ·
  venue→directions) · who-came avatar row · a **party drink-grid** (each square = one drink logged that
  night; intensity = how much) · drink list **attributed but gentle** (who had what, NEVER a ranked
  "who drank most") · mood cloud of the night · photo wall.

### Shareable artifacts have a STYLE/TEMPLATE GALLERY (decided 2026-06-27) — the expressive outlet
Reconciles "playful + collectible" with the calm app: **the in-app experience stays Swiss-minimal ALWAYS;
the exported artifacts (share cards + party posters) are where bold/playful variety lives.** Share cards
and party recaps offer a small gallery of templates + grid layouts: **minimal** (default) → **poster/
collage** (bold, GTA-cover-inspired *composition*: multi-panel collage, big title, duotone/halftone) →
**ticket/receipt** (fits the tally-ledger soul) → **contact-sheet/filmstrip** → **magazine cover**. Two
hard guardrails: (1) these styles are EXPORT-ONLY, the app never adopts them; (2) any bold/poster style is
our ORIGINAL art inspired by the composition language — NEVER copy GTA's (or anyone's) actual artwork or
assets (IP). Phase 3–4 (ships with sharing/parties); does not block the Phase 1 core build.
- **Competitions / challenges — OPT-IN, INSIDE CIRCLES ONLY.** Leaderboards (longest streak, most kinds,
  most logged) + challenges ("7 nights running", "5 new kinds", seasonal) scoped to a circle you joined.
  NOTHING competitive on the calendar or the main feed — you only see it if you opt into a circle's challenge.
- **To-try / wishlist:** save drinks (often from a friend's log) to a personal "to try" list (social→personal bridge).
- **Friend recommendations:** quietly surface what friends loved (their high-mood drinks) as things to try.
**Habit mechanics:** streaks (current + longest, surfaced quietly) · opt-in gentle **nightly reminder**
notification (drives the every-night habit) · quiet **typographic milestones** (10/50/100 logs) — calm,
NOT colorful gamified badges.
**Account:** auth, profile, data export. Light-first; dark mode is a later maybe.

## Information architecture (locked 2026-06-27)
**Three top-level tabs** (bottom bar on mobile / quiet side rail on desktop), calendar dominant:
- **Calendar (home)** — the month, today emphasized. THE front door. Stays a calm pure diary; NO scores/
  leaderboards ever appear here.
- **Together** (the Feed tab, grown into a hub) — friends feed · circles · parties/events · opt-in
  challenges. All the lively/communal/competitive energy lives here, never on the Calendar.
- **You** — your mosaic, streaks (with **grace**: one missed night forgiven), milestones, **photo wall**,
  to-try list, shelf, profile, settings, social connections.

Adopted extras (locked): **streak grace** (one skip forgiven, keeps the habit calm not punishing) ·
**photo wall** (visual grid of all your drink photos) · **maps**: venue/where fields link out so a tap
opens the user's map app for **directions**.

Not tabs (reached contextually): **Year mosaic** = a zoom-out one tap from the Calendar (not a separate
tab); **Day detail** = tap a day with entries; **Shelf** (searchable history + mood lexicon + stat line)
= reached via the year mosaic and from You.

**Logging entry point: tap a day's cell only** (today included). NO floating "+" button, no second path.
One mental model everywhere: tap a day → form sheet slides up from it. This keeps zero chrome and the
calendar central.

## Onboarding & first-run (locked 2026-06-27): "experience first, register at the moment of value"
- **Auth model: log first, account later.** No sign-up wall.
- **Logged-out / first visit → an intro LANDING PAGE that is actually live.** Swiss-minimal landing that
  introduces brewdiary (what it is, how it works) AND embeds a real, working calendar right on the page.
- Tap a day on that landing calendar → the real log modal opens → the visitor actually **logs a drink**,
  experiencing the core ritual before committing to anything.
- On **save/done of that first log → THEN prompt to register** (gated at the point of value, not before).
  Preserve that first entry and attach it to the new account on signup — never lose it.
- **After registering, returning users land straight in the regular app** (the three-tab calendar
  experience) — the landing page is only for logged-out/first-time visitors.
- This is the ONE place a real marketing landing page is in scope. It still obeys all anti-slop rules
  (taste-skill heritage was literally built for landing pages) — same Swiss-minimal discipline as the app.

## Dials for this product (low and quiet)
DESIGN_VARIANCE 4 · MOTION_INTENSITY 3 · VISUAL_DENSITY 2.

## Design language v2 (2026-06-27 update — supersedes "strict monochrome")
Evolved from strict cold-monochrome to **WARM minimalism** (research-backed: warm minimalism is the
antidote to "sterile / AI-looking"):
- **Warm palette, NOT blue-white.** Light: bone `#FAF6EE` + warm espresso ink `#1B1714`. Dark: warm
  near-black `#14110E` + warm bone text `#ECE4D8`. **Dark mode is now in scope** (light/dark/system, class
  on `<html>`, no-flash script).
- **One restrained amber accent** (`#B8742A` light / `#D9933F` dark), used for tiny moments — the
  streak number, "today" ring, the Discover CTA. *(NOTE: v2 said the accent NEVER colours the mosaic;
  the v3 glass pivot reversed exactly this — the mosaic now glows amber-by-count. See v3 below.)*
- **No paper grain/texture** (user chose flat).
- **Editorial type as a statement:** oversized fluid display (`clamp`) for the month name; dramatic scale
  vs the small grotesque UI. **Fewer borders, more whitespace** (premium = calm/breathing room).
- Two mosaic ramps: gentle for the month grid (numbers stay legible both themes), dramatic for the year mosaic.
- Implementation: tokens as runtime CSS vars swapped by `.dark` (see `ARCHITECTURE.md`).

## Design language v3 (2026-06-30 — LIQUID GLASS pivot, AUTHORITATIVE, supersedes v1/v2 where they conflict)
The user explicitly overrode two v1/v2 rules ("make sure the app has only two themes and glassmorphism
kinda elements that everyone loves"). This is a deliberate, on-record decision — **honor it; do not
"correct" the app back to flat monochrome.** What changed, and what did NOT:
- **Glassmorphism is IN — done tastefully.** `globals.css` is a liquid-glass token system: a vibrant
  drink-hued **ambient blob background** (`--ambient`: 4 radial gradients amber/rose/teal/violet over
  `--base`, fixed `body::before`) and frosted component classes **`.glass` / `.glass-strong` /
  `.glass-press`** (backdrop-blur + saturate, translucent bg, hairline glass border, soft shadow + inset
  highlight). Rule of tasteful glass, still enforced: glass lives on **layered surfaces only**, text
  stays **high-contrast**, exactly **one accent**, no AI-purple/neon/random gradients. Non-glass by
  design: **DayCell** (mosaic squares) and the **ShareCard** export canvas.
- **The mosaic now GLOWS AMBER by count** (`--mosaic: var(--accent)`; gentle `--cell-*` month ramp +
  dramatic `--ycell-*` year ramp). This reverses v1's "monochrome ink mosaic" and v2's "accent never
  touches the mosaic." **Intensity-by-count is unchanged and permanent** — only the hue moved from ink to
  amber. Still NOT colour-by-drink-type, still one hue.
- **Exactly TWO themes, dark default.** `theme.ts` is `Theme = "light" | "dark"` (no "system"/`resolve()`);
  `DEFAULT_THEME = "dark"` (glass reads strongest on dark); no-flash script assumes dark unless the user
  explicitly picked light; `ThemeToggle` is a single ○/● toggle, not a 3-way cycle.
- **Radius:** `--radius-tile: 20px` for glass tiles.
- **What did NOT change (still law):** calm > decoration; type carries the app; one accent only; no
  emoji icons; no AI-purple; the mosaic is count-driven; bold/expressive art stays **export-only** (share
  cards / party posters), never in-app; "must not look AI-generated" is still the prime fear — glass is
  allowed *because the user asked for it and it's applied with restraint*, NOT as license for slop.
- Adopted across ~14 components (TopBar, sheets, cards, TabBar, calendar chrome, feed, you, discover,
  bartender). `anti-slop.md`'s blanket "no glassmorphism / monochrome only" lines are **historical** —
  read them as "no *lazy/generic* glass," not "no glass."

## Discover + monetization (2026-06-27 — the business engine)
A **top-right "Discover" button** opens the Discover surface = how brewdiary makes money:
- **Compass** always pointing to the nearest **top-rated (>4★)** bar/club/bottle-shop (Google Places + geolocation).
- A **venue list** that deep-links into the user's **Google/Apple Maps** for directions.
- **Recipe pop-ups** that surface/promote drinks; **AI bartender** (now IN scope — reverses earlier non-goal).
- **B2B: sell AGGREGATED/ANONYMISED taste-trend data** to brands at premium.
- **RESPONSIBLE-BUILD GUARDRAILS (must honour):** age-gate the app (21+/alcohol); label sponsored content
  as "sponsored" (no covert promotion); location & data-sharing are **opt-in**; sell only aggregated/
  anonymised trends, never personal data. Keeps the full monetisation while staying app-store- &
  GDPR/CCPA-compliant. These are PHASE features (need API keys/geo/backend), not the calm core.

## Build order (so scope can't creep)
1. **Core loop first, no backend, local data:** calendar home → tap a day → tiny log form → streak
   mosaic filling in. Get the ritual feeling right in the hand before anything else.
2. Then real storage.
3. Then the social layer.

## Stack (proposed, pending the user's final "go")
Next.js (App Router) + TypeScript + Tailwind. Minimalism is enforced by us, not the framework.
(Lighter Vite + React is an acceptable alternative if the user prefers.)
