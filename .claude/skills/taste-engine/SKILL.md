---
name: taste-engine
description: >
  Anti-slop design intelligence for the brewdiary app. Use for ANY UI/UX work —
  building or refactoring screens, components, layouts, the calendar, the log form,
  the streak mosaic, the social layer; choosing type, color, spacing, motion, states;
  or reviewing UI for quality. Fuses taste-skill's anti-slop judgment (re-aimed at
  product/app UI, not landing pages) with a queryable design-knowledge engine, and
  pre-locks brewdiary's Swiss-minimal north star so output never drifts to AI slop.
---

# taste-engine — judgment + evidence, locked to brewdiary

This skill is a **blend of two real skills, made better than either**:

- **taste-skill** (`Leonxlnx/taste-skill`) gave the *judgment*: read-the-room, anti-default
  discipline, anti-slop directives. But it is scoped to landing pages / portfolios. brewdiary
  is **product/app UI** (a calendar, a form, a feed), so that judgment is **re-aimed at app UI** here.
- **ui-ux-pro-max** (`nextlevelbuilder/ui-ux-pro-max-skill`) gave the *evidence*: a queryable
  dataset of styles/colors/typography/UX rules + a Python search engine, plus deep app-UX rules
  (touch targets, forms, navigation, states) that taste-skill lacks.

The fusion: **decide with taste, ground every decision in the engine, and never violate the
brewdiary north star.** Depth lives in `reference/` — read those files when you need detail.

---

## 0. The brewdiary north star (NON-NEGOTIABLE — read `reference/brewdiary-north-star.md`)

Every screen obeys these. They override any generic recommendation, including the engine's:

- **Swiss minimal.** Bone white + near-black. Type carries the design. Fine rules, small caps,
  generous whitespace, gallery-calm. Discipline over decoration — decoration is how it would start
  looking AI-generated.
- **The home is a calendar.** Tap a day → tiny form slides in → log a drink. One tap, done.
- **Collectible = streak mosaic, intensity by count.** Monochrome grid; a day's square gets
  *darker the more you logged that day*. NOT color-by-type, NOT a flat single accent.
- **The form is ~5 fields**: what it was · feeling/mark · optional note · optional photo · share toggle.
- **Social is the second layer, never the front door.**
- **Calm, warm, habit-forming.** Warmth comes from the mosaic + restrained micro-interaction,
  not from ornament, gradients, or color.

If a request conflicts with the north star, say so and propose the on-spec alternative before coding.

---

## 1. Workflow for any UI task

**Step A — Read the room (one line).** Before code, state the design read:
*"Reading this as: \<screen> for \<the user's nightly ritual / the social glance>, Swiss-minimal,
type-driven, leaning monochrome + intensity-mosaic."* If genuinely ambiguous, ask **one** question — never a dump.

**Step B — Query the engine for evidence** (it is third-party Python — see §3 for the trust note).
Run from `scripts/` so imports resolve:
```bash
python search.py "<query>" --design-system          # full recommendation + anti-patterns
python search.py "<query>" --domain <domain> -n 5    # deep-dive one dimension
python search.py "<query>" --stack nextjs            # stack-specific implementation rules
```
Domains: `style · color · typography · google-fonts · ux · landing · product · chart · react · web · prompt`.
Treat the engine as **evidence, not orders**: take what aligns with the north star, discard the rest
(it will sometimes suggest gradients/accents/landing patterns — ignore those, we are minimal product UI).

**Step C — Decide with taste.** Apply the anti-slop rules in `reference/anti-slop.md`. Set the dials
low for this product: **DESIGN_VARIANCE 4 · MOTION_INTENSITY 3 · VISUAL_DENSITY 2** (calm, airy, quiet).

**Step D — Pre-flight before declaring done** (see §2). If any check fails, it is not done.

---

## 2. Pre-flight checklist (mechanical — run it every time)

**Anti-slop (taste):**
- [ ] No AI-purple / blue glow, no mesh gradients, no glassmorphism-on-everything.
- [ ] No `Inter` / `Roboto` / `Open Sans` as the type voice. No `lucide` as the icon set.
- [ ] One accent at most, and we barely use one — the mosaic's ink is the only "color".
- [ ] Body text is off-black (`#111`-ish), never pure `#000`; secondary is a real muted grey, not gray-on-gray.
- [ ] No heavy drop shadows (`shadow-md/lg/xl`). Shadows near-zero or ultra-diffuse (<0.05 opacity).
- [ ] One corner-radius scale, used everywhere. No pill containers.
- [ ] No emojis as icons. No `Lorem Ipsum` / `John Doe` — use real, contextual drink content.
- [ ] No AI clichés in copy ("Elevate", "Seamless", "Unleash", "Effortless"). Plain, specific words.

**App-UX (from the engine's CRITICAL/HIGH tiers — read `reference/app-ux.md`):**
- [ ] Touch targets ≥ 44×44; ≥ 8px between them.
- [ ] Every interactive element has hover/press/focus/disabled states; focus rings visible.
- [ ] Form: label above input (never placeholder-as-label), error below the field, success feedback.
- [ ] Empty states are composed and tell you how to populate (the un-logged calendar must feel inviting, not blank).
- [ ] Loading uses skeletons matching final shape, not spinners.
- [ ] Contrast ≥ 4.5:1 body / 3:1 large. Color is never the only signal.
- [ ] `prefers-reduced-motion` respected. Motion 150–300ms, transform/opacity only.
- [ ] `min-h-[100dvh]` not `h-screen`. CSS Grid over flex-percentage math.

**North-star:**
- [ ] Still Swiss-minimal, calm, type-driven. Mosaic is intensity-by-count. Calendar is the home. Social stays second.

---

## 3. Trust note on the engine

`scripts/` + `data/` are copied from the external `ui-ux-pro-max` repo. Running `search.py` executes
third-party Python and will prompt for permission the first time. That is expected — let the user approve it.
The engine is **read-only** (BM25 search over local CSVs); it does no network or file mutation except the
optional `--persist` flag (which writes a `design-system/` folder, only when explicitly passed).
If running it is ever blocked, fall back to `reference/anti-slop.md` + `reference/app-ux.md`, which already
distill the rules that matter for brewdiary.

---

## 4. Files in this skill

- `SKILL.md` — this brain.
- `reference/brewdiary-north-star.md` — the locked product/design spec. The constitution.
- `reference/data-model.md` — the entity schema + relationships (what's stored vs derived), with phase tags.
- `reference/anti-slop.md` — taste-skill's judgment, distilled and re-aimed at product UI + minimalist rules.
- `reference/app-ux.md` — the app-UX rules that matter for a journaling app (forms, states, nav, a11y, motion).
- `scripts/` `data/` — the ui-ux-pro-max search engine + its knowledge CSVs.
