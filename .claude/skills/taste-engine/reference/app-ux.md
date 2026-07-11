# App-UX rules that matter for brewdiary (from ui-ux-pro-max, trimmed to a journaling app)

ui-ux-pro-max ships ~99 UX rules across 10 priority tiers. This is the subset that actually bites for a
calm, calendar-driven, mobile-friendly journaling + light-social app. Full depth is queryable via
`python search.py "<kw>" --domain ux -n 8` from `scripts/`.

## CRITICAL — accessibility
- Contrast ≥ 4.5:1 normal text, 3:1 large. Test the muted-grey secondary text explicitly.
- Visible focus rings on every interactive element (2–4px). Never remove them.
- Color is never the only signal — the mosaic's intensity must also be legible to low-vision users
  (the count is the meaning; expose it as text/aria too, e.g. "June 12 — 3 logged").
- Icon-only buttons get `aria-label`. Heading hierarchy sequential. Respect `prefers-reduced-motion`.

## CRITICAL — touch & interaction
- Touch targets ≥ 44×44 (a calendar day cell must meet this even when visually small — expand hit area).
- ≥ 8px between targets. Don't rely on hover alone — tap is primary (this will be used on phones).
- Visual feedback within ~100ms of tap. `touch-action: manipulation` to kill the 300ms delay.

## HIGH — performance / perceived speed
- Skeleton/shimmer for anything > ~300ms, not blocking spinners.
- Reserve space for async content (declare image width/height / aspect-ratio) → no layout shift (CLS).
- Lazy-load below-fold; if a year view ever renders 365+ cells, virtualize / chunk by month.
- Optimistic UI for logging: the square should darken immediately on submit, reconcile after.

## HIGH — layout & responsive
- Mobile-first. Systematic breakpoints (375 / 768 / 1024 / 1440). No horizontal scroll on mobile.
- 4/8px spacing rhythm. `min-h-dvh` over `100vh`. Consistent max content width on desktop.
- The calendar must reflow gracefully: month grid on mobile, more context (week strip / year mosaic) on wider screens.

## MEDIUM — forms & feedback (the log form is the core interaction — get this perfect)
- Visible label per field; never placeholder-only. Required indicators if any field is required.
- Error below the related field; submit shows loading → success/error. Validate on blur.
- Empty states everywhere helpful: no entries yet, no friends yet, no photo — each with a gentle next step.
- Toasts auto-dismiss 3–5s, `aria-live="polite"`, never steal focus. Confirm before destructive deletes; offer undo.
- Semantic input types (so mobile keyboards are right). Autosave a draft if the form is non-trivial.

## MEDIUM — typography & color tokens
- Define semantic tokens (surface, on-surface, border, muted, accent) — no raw hex in components.
- Base 16px body, line-height 1.5–1.75, type scale (12 14 16 18 24 32). Tabular figures for dates/counts.

## MEDIUM — animation
- 150–300ms micro-interactions; ≤ 400ms for bigger transitions; never > 500ms.
- Modals/sheets animate from their trigger (the form sheet slides from the tapped day). Exit ~60–70% of enter.
- Animate 1–2 key elements per view max. Spring/physics curves feel more natural than linear.

## HIGH — navigation
- Active location highlighted. Back is predictable and restores scroll/state.
- If a bottom nav is used (mobile), ≤ 5 items, icon + label. Keep calendar as the primary/home tab;
  social and profile are peers, not the front door.
- Every key screen reachable by URL/deep link (so a shared tasting card opens to the right place).
- Don't mix tab + sidebar + bottom nav at the same hierarchy level. Modals are not primary navigation.

## Light/dark
- We are light-first (bone white). If a dark mode is ever added, design it as a pair — desaturated tonal
  variants, not inverted; re-test contrast independently. One theme per session, sections never invert.
