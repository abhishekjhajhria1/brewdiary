# Anti-slop judgment (distilled from taste-skill, re-aimed at product/app UI)

taste-skill is written for landing pages. brewdiary is product UI. These are its rules that still
apply, translated to our context, plus the minimalist-ui rules folded in. Apply with the low dials
(VARIANCE 4 · MOTION 3 · DENSITY 2).

> **2026-06-30 glass pivot note (read first):** the user explicitly adopted a restrained **liquid-glass**
> look + amber-by-count mosaic + two themes (dark default). So "no glassmorphism / monochrome by decree"
> below is HISTORICAL. Re-read every anti-glass / monochrome line as **"no *lazy, generic, everything-is-
> frosted* glass, no AI-purple/neon"** — tasteful glass on layered surfaces is now the house style. The
> constant is unchanged: it must not look AI-generated. See `brewdiary-north-star.md` → "Design language v3".

## The anti-default discipline (the core idea)
LLMs jump to a default aesthetic. Reach past it deliberately. Do NOT default to: AI-purple/blue
gradients, centered hero over dark mesh, three equal feature cards, **generic/every-surface**
glassmorphism, infinite-loop micro-animations, `Inter` + `slate-900`. These are the tells. (brewdiary's
glass is deliberate + restrained — layered surfaces only, high-contrast text, one accent; that is the
opposite of the lazy glass this line warns against.)

## Typography
- **Banned as default voice:** `Inter`, `Roboto`, `Open Sans`. Pick type with character — a precise
  neo-grotesque for UI/body (e.g. Geist, Switzer, Helvetica Neue-class), optionally a restrained
  display face. Confirm the actual wordmark/type voice with the user — it's the #1 "AI-generated" tell.
- Body text never pure black: off-black `#111`–`#2F3437`, line-height ~1.6. Secondary muted grey
  `~#787774`, still ≥ 4.5:1 contrast. No gray-on-gray.
- Use tabular/monospaced figures for the calendar numbers and any counts (prevents layout shift).
- Emphasis = italic/bold of the SAME family. Never inject a random serif word into a sans line.
- Serif is VERY discouraged as default. Only if genuinely editorial AND justified. Specifically banned
  defaults: `Fraunces`, `Instrument Serif`.

## Color
- **THE LILA RULE (permanent):** no AI-purple, no blue glow, no random neon gradients. Max one accent.
  *(Amended 2026-06-30: brewdiary is no longer flat-monochrome — it's warm glass + a single amber accent,
  and the mosaic glows amber-by-count. The LILA anti-purple/neon rule still holds absolutely; "monochrome
  by decree" does not.)*
- One palette, locked, used everywhere. No warm-grey drifting to cool-grey mid-app.
- **Premium-consumer palette ban:** the beige/cream + brass/clay/oxblood + espresso default is the
  second-most-common AI tell. Do NOT reach for it just because this is a "drinks" app. Stay
  bone-white + near-black; if an accent is ever needed, it is a single deliberate one, not warm-craft slop.

## Layout
- CSS Grid over flex-percentage math (`w-[calc(33%-1rem)]` banned). `min-h-[100dvh]`, never `h-screen`.
- Establish macro-whitespace first (generous vertical rhythm). Constrain text measure (~65ch).
- One corner-radius scale for the whole app; pick it and never mix. No `rounded-full` containers/cards.
- Cards ONLY when elevation means real hierarchy; otherwise group with `border-t` / `divide-y` / space.
- No section-layout repetition: don't repeat the same block pattern down a screen.
- **Eyebrow restraint:** the small uppercase tracked label above every header is the #1 over-used tell.
  Max ~1 per 3 sections. Usually the headline alone is enough.

## Materiality & shadows
- No `shadow-md/lg/xl`. Shadows near-zero or ultra-diffuse (< 0.05 opacity), tinted to the bg hue,
  never pure-black on light. The Swiss look is flat + hairline borders (`1px` light grey), not elevated.

## Interactive states (always full cycles — LLMs ship "happy path only")
- Loading: skeletons matching final shape, not spinners.
- Empty: composed and inviting + shows how to populate. The un-logged calendar is the most-seen empty
  state — it must feel like an invitation to start a streak, not a blank grid.
- Error: inline (forms) / contextual (transient toasts).
- Tactile: `:active` → `scale-[0.98]` or `-translate-y-[1px]`. Press feedback within ~100ms.
- Button contrast check (a11y): never white-on-white, never label that fails contrast; CTA text fits one line.

## Forms
- Label ABOVE input (placeholder-as-label banned, ever). Helper text in markup. Error BELOW the field.
- Submit shows loading → success/error. Validate on blur, not per keystroke. Auto-focus first invalid field.

## Motion (low for this product — MOTION_INTENSITY 3)
- Motion must be motivated: hierarchy, feedback, state-transition, or sequence. Never "looked cool".
- 150–300ms, ease-out entering / ease-in exiting, transform + opacity only (no width/height/top/left).
- Scroll-entry: `translateY(12px)` + opacity over ~600ms `cubic-bezier(0.16,1,0.3,1)`, via
  IntersectionObserver. Stagger lists ~80ms. Respect `prefers-reduced-motion`.
- The form slide-in and a square gently darkening as you log are the signature motions. Keep the rest still.

## Copy
- Plain, specific, human. Banned clichés: "Elevate, Seamless, Unleash, Next-Gen, Game-changer, Delve,
  Effortless". No `Lorem Ipsum`, no `John Doe` / `Acme` — use real drink names and realistic notes.
- Self-audit every visible string before shipping; replace anything cute-but-wrong with a plain sentence.
- No em-dash as a design flourish in microcopy. Real typographic quotes, not straight ASCII.

## Icons
- One family, consistent stroke width. `lucide` discouraged (minimalist-ui bans it); prefer Phosphor or
  Radix. Never hand-roll SVG icon paths. Never emoji as a structural icon.
