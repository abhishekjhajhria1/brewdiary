"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import clsx from "clsx";
import { signIn, signUp, sendPasswordReset } from "@/lib/profile";
import { useReveal } from "../ui/useReveal";

type AuthMode = "signup" | "signin";

/**
 * The logged-out landing page — a printed prospectus for the diary, not a demo of it.
 *
 * HOW IT'S BUILT — one client component with no route of its own. `app/page.tsx` reads the
 * session cookie on the SERVER and renders either `CalendarHome` or this, so a visitor's
 * first paint is the landing and a diarist's is the app: no flash, no client redirect.
 *
 * WHAT IT DELIBERATELY IS NOT — an app tour. Earlier versions embedded the live calendar and
 * the log sheet so a stranger could log a drink before registering. That's gone. The screens
 * (calendar, Passport, Together, Ninkasi, You) are what you get AFTER you make a diary; this
 * page's entire job is to make the case and take the sign-up. It reads no entry and writes
 * none, so there's no orphan diary stranded in a browser someone never opens again. The only
 * tap targets on the whole page are sign in and create diary.
 *
 * WHAT INSPIRED THE SHAPE — a bound field guide: a title page, then numbered chapters, each
 * one a different set piece rather than another row of feature cards. Two of those set pieces
 * do the arguing that copy can't — a real year of squares filling in as a wave (the collection
 * you're being offered), and a road drawing itself toward a frontier (the map you're being
 * offered). Everything else is type on hairlines.
 *
 * THE MOTION RULE HERE — every animation on this page is FINITE and motivated: it plays once
 * on entry and stops. Nothing loops, nothing pulses, nothing follows the cursor. Under
 * `prefers-reduced-motion` each set piece resolves instantly to its finished state (see
 * `useReveal`), which is why the hero word settles rather than cycling forever.
 */
export function Landing() {
  const [authMode, setAuthMode] = useState<AuthMode | null>(null);
  const openSignup = () => setAuthMode("signup");

  return (
    <>
      <Masthead onSignin={() => setAuthMode("signin")} onStart={openSignup} />

      <Hero onStart={openSignup} />

      <TheYear />

      <TheRitual />

      <TheLexicon />

      <TheMap onStart={openSignup} />

      <TheTable />

      <TheLine />

      <Availability onStart={openSignup} />

      <Close onStart={openSignup} />

      <Colophon />

      {authMode && (
        <AuthSheet mode={authMode} onSwitch={(m) => setAuthMode(m)} onClose={() => setAuthMode(null)} />
      )}
    </>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   Shared furniture
   ────────────────────────────────────────────────────────────────────────── */

/** Scroll-entry wrapper: rises once, then never moves again. Delay is skipped
 *  under reduced motion (a delay isn't a duration — see `useReveal`). */
function Reveal({
  children,
  delay = 0,
  className,
}: {
  children: React.ReactNode;
  delay?: number;
  className?: string;
}) {
  const { ref, shown, reduced } = useReveal<HTMLDivElement>();
  return (
    <div
      ref={ref}
      style={{ transitionDelay: shown && !reduced ? `${delay}ms` : "0ms" }}
      className={clsx(
        "transition-[opacity,transform] duration-700 ease-[cubic-bezier(0.16,1,0.3,1)]",
        shown ? "translate-y-0 opacity-100" : "translate-y-3 opacity-0",
        className,
      )}
    >
      {children}
    </div>
  );
}

/** The chapter rule — a numeral, a hairline, a name. The page's spine: it's how a
 *  reader knows they're in a book and not in an endless scroll of feature blocks. */
function ChapterRule({ n, name }: { n: string; name: string }) {
  return (
    <div className="mb-7 flex items-center gap-4">
      <span className="label tnum text-accent">{n}</span>
      <span aria-hidden className="h-px flex-1 bg-line" />
      <span className="label text-faint">{name}</span>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   Masthead + title page
   ────────────────────────────────────────────────────────────────────────── */

function Masthead({ onSignin, onStart }: { onSignin: () => void; onStart: () => void }) {
  return (
    <header className="sticky top-0 z-30 -mx-5 mb-2 flex items-center justify-between gap-3 border-b border-line/60 bg-canvas/70 px-5 py-3 backdrop-blur-xl">
      <span className="font-display text-lg italic text-muted">brewdiary</span>
      <div className="flex items-center gap-1.5">
        <button
          type="button"
          onClick={onSignin}
          className="rounded-ctl px-3 py-2 text-xs font-medium uppercase tracking-[0.12em] text-muted transition-colors hover:text-ink"
        >
          Sign in
        </button>
        <button
          type="button"
          onClick={onStart}
          className="rounded-ctl bg-ink px-4 py-2 text-xs font-medium uppercase tracking-[0.12em] text-paper transition-transform duration-150 ease-out hover:opacity-90 active:scale-[0.98]"
        >
          Create diary
        </button>
      </div>
    </header>
  );
}

// The hero word doesn't loop — it walks a short list of real drinks and SETTLES on
// "pour", which is the actual claim: this diary isn't about one category. A loop
// would be decoration; a sequence that ends is a sentence being written.
const HERO_WORDS = ["espresso", "saison", "negroni", "kombucha", "pour"] as const;

function useSettlingWord() {
  const [i, setI] = useState(0);

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setI(HERO_WORDS.length - 1); // straight to the finished sentence
      return;
    }
    if (i >= HERO_WORDS.length - 1) return;
    const t = window.setTimeout(() => setI((v) => v + 1), i === 0 ? 950 : 1050);
    return () => window.clearTimeout(t);
  }, [i]);

  return HERO_WORDS[i];
}

function Hero({ onStart }: { onStart: () => void }) {
  const word = useSettlingWord();

  return (
    <section className="flex min-h-[74svh] flex-col justify-center py-10">
      <p className="label mb-5 text-faint">Est. tonight · a diary for everything you drink</p>

      <h1 className="display leading-[0.92]">
        Every{" "}
        <span key={word} className="animate-fade italic text-accent">
          {word}
        </span>
        <br />
        gets a square.
      </h1>

      <p className="mt-7 max-w-md text-[15px] leading-relaxed text-muted">
        One tap a night, ten seconds, no forms. A year later you&apos;re holding a mosaic of your
        own taste — where you kept going back, and where you&apos;ve never been.
      </p>

      <div className="mt-9 flex flex-col gap-3 sm:flex-row sm:items-center">
        <button
          type="button"
          onClick={onStart}
          className="rounded-ctl bg-accent px-8 py-3.5 text-center text-sm font-medium uppercase tracking-[0.12em] text-accent-contrast shadow-[0_8px_28px_-8px_var(--accent),inset_0_1px_0_rgba(255,255,255,0.28)] transition-transform duration-150 ease-out hover:-translate-y-px active:translate-y-0"
        >
          Make your diary
        </button>
        <p className="text-xs leading-relaxed text-faint">
          Free · no card · 30 seconds · private from the first entry
        </p>
      </div>

      <span aria-hidden className="mt-14 block h-12 w-px bg-linear-to-b from-line-strong to-transparent" />
    </section>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   I — The year. The set piece that argues better than a paragraph: 364 real
   squares, filling in as a wave when you reach them, then still forever.
   ────────────────────────────────────────────────────────────────────────── */

const COLS = 52;
const ROWS = 7;

// Deterministic so the server and the client paint the identical grid — a random
// mosaic here would hydrate as a different year and React would tear it down.
const YEAR_CELLS = Array.from({ length: COLS * ROWS }, (_, i) => {
  const n = (i * 2654435761) >>> 0; // cheap stable hash
  const r = (n % 100) / 100;
  if (r < 0.36) return 0;
  if (r < 0.63) return 1;
  if (r < 0.82) return 2;
  if (r < 0.94) return 3;
  return 4;
});

function TheYear() {
  const { ref, shown, reduced } = useReveal<HTMLDivElement>(0.08);

  return (
    <section className="mt-16">
      <ChapterRule n="I" name="The collection" />
      <Reveal>
        <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
          This is what
          <br />a year looks like.
        </h2>
      </Reveal>

      <div ref={ref} aria-hidden className="mt-9 select-none">
        <div className="grid gap-0.5" style={{ gridTemplateColumns: `repeat(${COLS}, minmax(0, 1fr))` }}>
          {YEAR_CELLS.map((level, i) => {
            const col = i % COLS;
            const row = Math.floor(i / COLS);
            return (
              <span
                key={i}
                className={clsx(
                  "aspect-square rounded-xs transition-[opacity,transform] duration-500 ease-[cubic-bezier(0.16,1,0.3,1)]",
                  shown ? "scale-100 opacity-100" : "scale-50 opacity-0",
                )}
                style={{
                  backgroundColor: level === 0 ? "var(--line)" : `var(--ycell-${level})`,
                  transitionDelay: shown && !reduced ? `${col * 16 + row * 9}ms` : "0ms",
                }}
              />
            );
          })}
        </div>
      </div>

      <Reveal delay={80}>
        <p className="label mt-4 text-faint">364 nights · brighter is more · nothing typed twice</p>
        <p className="mt-6 max-w-lg text-[15px] leading-relaxed text-muted">
          Every square is one entry you made in ten seconds. Log a night and it brightens; miss one
          and the run survives, because a single slip should never wipe a month. Have water instead
          and the square still counts — a dry day keeps your streak here, which is the whole
          difference between this and a tracker.
        </p>
      </Reveal>
    </section>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   II — The ritual. A vertical timeline: the mechanic in three beats, so nobody
   signs up wondering what they've agreed to do every night.
   ────────────────────────────────────────────────────────────────────────── */

const BEATS: { t: string; b: string }[] = [
  {
    t: "Tap the day",
    b: "The home is a calendar, not a feed. Tonight is already sitting there waiting for you.",
  },
  {
    t: "Say what it was",
    b: "A name, a mark for how it felt, and a note or photo if the night earned one. Everything after the name is optional.",
  },
  {
    t: "Watch it land",
    b: "The square brightens and the sheet closes. That's the ritual — no units, no macros, no interrogation.",
  },
];

function TheRitual() {
  return (
    <section className="mt-20">
      <ChapterRule n="II" name="The ritual" />
      <Reveal>
        <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
          Ten seconds,
          <br />
          then it leaves
          <br />
          you alone.
        </h2>
      </Reveal>

      <ol className="mt-10">
        {BEATS.map(({ t, b }, i) => (
          <Reveal key={t} delay={i * 90}>
            <li className="relative flex gap-5 pb-9 last:pb-0">
              {/* the thread running through the three beats */}
              {i < BEATS.length - 1 && (
                <span aria-hidden className="absolute left-1.25 top-4 h-full w-px bg-line" />
              )}
              <span aria-hidden className="relative mt-1.75 h-2.5 w-2.5 shrink-0 rounded-full bg-accent" />
              <div>
                <h3 className="font-display text-xl text-ink">{t}</h3>
                <p className="mt-1.5 max-w-md text-[15px] leading-relaxed text-muted">{b}</p>
              </div>
            </li>
          </Reveal>
        ))}
      </ol>
    </section>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   The lexicon band — a wall of real names, a few lit. It shows the dictionary
   doing its job without a screenshot: you write it however you write it, and the
   diary knows which family it belongs to.
   ────────────────────────────────────────────────────────────────────────── */

const LEXICON = [
  "Cortado", "Gose", "Saison", "Flat white", "Rioja", "Mezcal", "Yuzu soda", "Hojicha",
  "Kombucha", "Negroni", "Riesling", "Cold brew", "Dry stout", "Barleywine", "Masala chai",
  "Amaro", "Sencha", "Pilsner", "Junmai sake", "Filter coffee", "Old fashioned", "Kvass",
  "Dry cider", "Lambic", "Espresso tonic", "Yerba mate", "Vermouth", "Gimlet", "Nitro cold brew",
  "Feni", "Toddy", "Rooibos",
];

function TheLexicon() {
  return (
    <section className="mt-20">
      <Reveal>
        <div className="glass rounded-tile p-5 sm:p-7">
          <p className="flex flex-wrap items-baseline gap-x-3 gap-y-2">
            {LEXICON.map((name, i) => {
              const lit = i % 7 === 3; // deterministic — same on server and client
              return (
                <span
                  key={name}
                  className={clsx(
                    "font-display",
                    lit ? "text-lg text-accent sm:text-xl" : "text-base text-muted",
                    !lit && i % 3 === 0 && "opacity-70",
                  )}
                >
                  {name}
                </span>
              );
            })}
          </p>
        </div>
      </Reveal>
      <Reveal delay={80}>
        <p className="mt-5 max-w-lg text-[15px] leading-relaxed text-muted">
          Write it however you write it. Type <span className="text-ink">guiness</span> at one in
          the morning and the diary knows you meant Guinness, and that Guinness is a dry stout, and
          that a dry stout is a place on your map. Nobody has to keep a tidy database — that&apos;s
          the app&apos;s job.
        </p>
      </Reveal>
    </section>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   III — The map. The second set piece: the real Journey road, drawn once on
   arrival. Travelled stretch gold, road ahead dashed, you at the frontier.
   ────────────────────────────────────────────────────────────────────────── */

const W = 640;
const H = 132;
const roadY = (x: number) => H / 2 + Math.sin((x / W) * Math.PI * 2.2) * 36;
const ROAD = `M ${Array.from({ length: 81 }, (_, i) => {
  const x = (i / 80) * W;
  return `${x.toFixed(1)},${roadY(x).toFixed(1)}`;
}).join(" L ")}`;
const MARKS = [0.06, 0.2, 0.36, 0.52, 0.67, 0.82, 0.95].map((t, i) => ({
  x: t * W,
  y: roadY(t * W),
  reached: i < 3,
}));
const FRONTIER = MARKS[2];

function TheMap({ onStart }: { onStart: () => void }) {
  const { ref, shown, reduced } = useReveal<HTMLDivElement>(0.2);

  return (
    <section className="mt-20">
      <ChapterRule n="III" name="The map" />
      <Reveal>
        <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
          Every first
          <br />
          is a landmark.
        </h2>
        <p className="mt-6 max-w-lg text-[15px] leading-relaxed text-muted">
          Your entries draw a road, and the only way to travel it is to try something you&apos;ve
          never had. Order a wine you can&apos;t pronounce and a region opens. Find a drink our
          dictionary has never heard of — a village arrack, your uncle&apos;s brew — and you can
          chart it yourself: name it, place it, and it&apos;s on the map for everyone after you.
        </p>
      </Reveal>

      <div ref={ref} aria-hidden className="glass map-grid mt-9 select-none overflow-hidden rounded-tile px-2 py-5">
        <svg viewBox={`0 0 ${W} ${H}`} className="w-full" role="presentation">
          {/* the road ahead — dim, dashed, always there */}
          <path d={ROAD} fill="none" stroke="var(--line-strong)" strokeWidth="2" strokeDasharray="6 7" />
          {/* travelled — gold, drawn once to the frontier (dashoffset, not dasharray: it
              animates on the compositor and doesn't re-flow the path every frame) */}
          <path
            d={ROAD}
            fill="none"
            stroke="var(--accent)"
            strokeWidth="2.5"
            strokeLinecap="round"
            pathLength={100}
            strokeDasharray="100 100"
            style={{
              strokeDashoffset: shown ? 48 : 100,
              transition: reduced ? "none" : "stroke-dashoffset 1.1s cubic-bezier(0.16,1,0.3,1)",
            }}
          />
          {MARKS.map((m, i) => (
            <circle
              key={i}
              cx={m.x}
              cy={m.y}
              r={m.reached ? 6 : 4.5}
              fill={m.reached ? "var(--accent)" : "var(--glass-strong)"}
              stroke={m.reached ? "var(--accent)" : "var(--line-strong)"}
              strokeWidth="1.5"
              style={{
                opacity: shown || !m.reached ? 1 : 0,
                transition: reduced ? "none" : `opacity 400ms ease ${300 + i * 90}ms`,
              }}
            />
          ))}
          {/* you are here */}
          <circle
            cx={FRONTIER.x}
            cy={FRONTIER.y}
            r="12"
            fill="var(--accent)"
            style={{
              opacity: shown ? 0.22 : 0,
              transition: reduced ? "none" : "opacity 600ms ease 900ms",
            }}
          />
          <circle cx={FRONTIER.x} cy={FRONTIER.y} r="6" fill="var(--accent)" />
        </svg>
        <p className="label mt-2 text-center text-faint">you are here — the road only asks for something new</p>
      </div>

      <Reveal delay={60}>
        <p className="mt-7 max-w-lg text-[15px] leading-relaxed text-muted">
          There&apos;s a lifetime score on that map and it&apos;s made of exactly two things: how
          wide you&apos;ve wandered, and how steadily you&apos;ve kept the diary. No axis for
          volume. No table of who drank most. Not now, not later.
        </p>
        <button
          type="button"
          onClick={onStart}
          className="mt-8 w-full rounded-ctl border border-line-strong py-3.5 text-sm font-medium uppercase tracking-[0.12em] text-ink transition-colors duration-150 hover:bg-ink hover:text-paper active:scale-[0.985] sm:w-auto sm:px-10"
        >
          Start my map
        </button>
      </Reveal>
    </section>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   IV — The table. The social half, as a plain index. Four things, no cards.
   ────────────────────────────────────────────────────────────────────────── */

const TABLE: { t: string; b: string }[] = [
  {
    t: "One pour, not your life",
    b: "Send a single entry to a friend, a private circle, or the table you're sitting at. Cheers and comments come back. There is no infinite feed, because the diary is the point and sharing is the afterthought.",
  },
  {
    t: "The round, settled",
    b: "Add the tab, add who was there, and the split falls out — who paid, who owes, cleared before anyone has put their card away.",
  },
  {
    t: "The night, logged once",
    b: "Open a party or a plan, pull in the people actually there, and the evening lands in everyone's diary at the same time instead of being retyped five ways.",
  },
  {
    t: "Bars that know you, with no file on you",
    b: "At a partner bar a loyalty card fills itself — earned in the room, punched by staff, never by you. What the bar sees is the nights it served you. Your diary never crosses the counter.",
  },
];

function TheTable() {
  return (
    <section className="mt-20">
      <ChapterRule n="IV" name="The table" />
      <Reveal>
        <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
          Drinking is
          <br />
          a social act.
          <br />
          Posting isn&apos;t.
        </h2>
      </Reveal>

      <div className="mt-10 grid gap-x-8 gap-y-9 sm:grid-cols-2">
        {TABLE.map(({ t, b }, i) => (
          <Reveal key={t} delay={i * 70}>
            <div className="border-t border-line pt-4">
              <span aria-hidden className="label tnum text-faint">
                {String(i + 1).padStart(2, "0")}
              </span>
              <h3 className="mt-2 font-display text-xl leading-snug text-ink">{t}</h3>
              <p className="mt-2 text-[15px] leading-relaxed text-muted">{b}</p>
            </div>
          </Reveal>
        ))}
      </div>
    </section>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   V — The line. The product's spine, printed in public so we're held to it.
   ────────────────────────────────────────────────────────────────────────── */

function TheLine() {
  return (
    <section className="mt-20">
      <ChapterRule n="V" name="The line" />
      <Reveal>
        <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
          Nothing here
          <br />
          rewards drinking
          <br />
          more.
        </h2>
      </Reveal>

      <div className="mt-9 space-y-6 border-l border-accent/50 pl-5">
        <Reveal>
          <p className="max-w-lg text-[15px] leading-relaxed text-muted">
            Every count in the app counts <span className="text-ink">variety</span> — a drink
            you&apos;ve never had, a place you&apos;ve never been, a night you had water instead.
            There is no total-drinks leaderboard and there never will be, because that is a
            scoreboard you win by pouring one more.
          </p>
        </Reveal>
        <Reveal delay={70}>
          <p className="max-w-lg text-[15px] leading-relaxed text-muted">
            Every entry starts <span className="text-ink">private</span>. Sharing is a separate tap,
            after the fact, one entry at a time. Take everything you&apos;ve ever written out in a
            single file, or delete the account outright — one screen, no email to support, no
            retention offer.
          </p>
        </Reveal>
        <Reveal delay={140}>
          <p className="max-w-lg text-[15px] leading-relaxed text-muted">
            And it&apos;s a diary for whatever you drink: the espresso at seven, the beer at nine,
            the kombucha you keep meaning to finish. If you don&apos;t drink alcohol at all, every
            part of this works exactly the same.
          </p>
        </Reveal>
      </div>
    </section>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   Availability — DELIBERATELY NOT BUTTONS.

   brewdiary ships as a web app today; the phone builds aren't out. A greyed-out
   App Store badge is a dead tap target and a small lie, so the unreleased rows are
   set as a printed manifest with dot leaders: nothing here is a link, a button, or
   focusable, and no amount of tapping does anything. What each row gives instead is
   the thing that DOES work today — Add to Home Screen, which is a real install.
   The only action in this chapter is the only one we actually have.
   ────────────────────────────────────────────────────────────────────────── */

const RELEASES: { name: string; status: string; note: string; ready: boolean }[] = [
  {
    name: "Web",
    status: "Live now",
    note: "Any browser, any device, and the diary follows you between them.",
    ready: true,
  },
  {
    name: "iPhone",
    status: "In the works",
    note: "Meanwhile: open brewdiary in Safari, tap Share, then Add to Home Screen. It opens full-screen, like an app, and works on a bad train connection.",
    ready: false,
  },
  {
    name: "Android",
    status: "In the works",
    note: "Meanwhile: open brewdiary in Chrome, tap the menu, then Add to Home screen.",
    ready: false,
  },
];

function Availability({ onStart }: { onStart: () => void }) {
  return (
    <section className="mt-20">
      <ChapterRule n="VI" name="Where to get it" />
      <Reveal>
        <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
          Nothing
          <br />
          to download.
        </h2>
        <p className="mt-6 max-w-lg text-[15px] leading-relaxed text-muted">
          brewdiary lives on the web, so there is no install queue and no update to sit through.
          The store builds are being made — when they land, your diary is already inside them.
        </p>
      </Reveal>

      <ul className="mt-9 space-y-7">
        {RELEASES.map(({ name, status, note, ready }, i) => (
          <Reveal key={name} delay={i * 70}>
            <li>
              <div className="flex items-baseline gap-3">
                <span className="font-display text-xl text-ink">{name}</span>
                <span aria-hidden className="h-px flex-1 border-b border-dotted border-line-strong" />
                <span className={clsx("label", ready ? "text-accent" : "text-faint")}>{status}</span>
              </div>
              <p className="mt-2 max-w-lg text-[15px] leading-relaxed text-muted">{note}</p>
            </li>
          </Reveal>
        ))}
      </ul>

      <Reveal delay={80}>
        <button
          type="button"
          onClick={onStart}
          className="mt-9 w-full rounded-ctl border border-line-strong py-3.5 text-sm font-medium uppercase tracking-[0.12em] text-ink transition-colors duration-150 hover:bg-ink hover:text-paper active:scale-[0.985] sm:w-auto sm:px-10"
        >
          Open it in this browser
        </button>
      </Reveal>
    </section>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   The close
   ────────────────────────────────────────────────────────────────────────── */

function Close({ onStart }: { onStart: () => void }) {
  return (
    <Reveal className="mt-20">
      <section className="glass rounded-tile p-6 sm:p-9">
        <h2 className="display text-[2.25rem] leading-[1.02] sm:text-[3rem]">
          Tonight is
          <br />
          the first square.
        </h2>
        <p className="mt-5 max-w-md text-[15px] leading-relaxed text-muted">
          An email and a password. That&apos;s the whole sign-up, and the diary is open on the other
          side of it.
        </p>
        <button
          type="button"
          onClick={onStart}
          className="mt-8 w-full rounded-ctl bg-accent py-4 text-sm font-medium uppercase tracking-[0.12em] text-accent-contrast shadow-[0_8px_28px_-8px_var(--accent),inset_0_1px_0_rgba(255,255,255,0.28)] transition-transform duration-150 ease-out hover:-translate-y-px active:translate-y-0 sm:w-auto sm:px-12"
        >
          Make your diary
        </button>
        <p className="mt-5 text-xs text-faint">
          Free · no card · private by default · nothing to install
        </p>
      </section>
    </Reveal>
  );
}

function Colophon() {
  return (
    <footer className="mt-14 flex flex-col gap-4 border-t border-line pt-6 text-xs text-faint sm:flex-row sm:items-center sm:justify-between">
      <span className="font-display text-base italic text-muted">brewdiary</span>
      <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
        <Link href="/privacy" className="transition-colors hover:text-ink">
          Privacy
        </Link>
        <Link href="/terms" className="transition-colors hover:text-ink">
          Terms
        </Link>
        <span>Please drink responsibly.</span>
      </div>
    </footer>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   The sheet — the only thing on this page that talks to a server.
   Auth logic is untouched from the version that's been working; only the copy
   around it changed. Sign-up is the single conversion path, so it is the last
   place to get clever.
   ────────────────────────────────────────────────────────────────────────── */

function AuthSheet({
  mode,
  onSwitch,
  onClose,
}: {
  mode: AuthMode;
  onSwitch: (m: AuthMode) => void;
  onClose: () => void;
}) {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState(false);
  const [resetSent, setResetSent] = useState(false);
  const router = useRouter();

  const isSignup = mode === "signup";

  async function forgot() {
    if (busy) return;
    if (!email.trim()) {
      setError("Enter your email above first, then tap reset.");
      return;
    }
    setBusy(true);
    setError(null);
    const res = await sendPasswordReset(email);
    setBusy(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setResetSent(true);
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    const res = isSignup ? await signUp(email, password, name) : await signIn(email, password);
    if (!res.ok) {
      setError(res.error);
      setBusy(false);
      return;
    }
    if (res.needsConfirm) {
      setConfirm(true);
      setBusy(false);
      return;
    }
    // Success with a session. The gate (app/page.tsx) is a SERVER component that
    // reads the session cookie, so it won't re-run on its own — refresh to re-run
    // it: Landing → CalendarHome, and this sheet unmounts. (No manual reload.)
    router.refresh();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center">
      <button aria-label="Close" className="absolute inset-0 bg-black/55 backdrop-blur-[3px]" onClick={onClose} />
      <div className="glass-strong animate-sheet relative w-full max-w-md rounded-t-[28px] bg-canvas/95 p-6 sm:rounded-[28px] sm:p-8">
        {confirm ? (
          <>
            <h2 className="display text-3xl leading-tight">Check your email.</h2>
            <p className="mt-3 text-[15px] leading-relaxed text-muted">
              We sent a confirmation link to <span className="text-ink">{email}</span>. Tap it to
              finish, then come back and sign in.
            </p>
            <button
              onClick={() => onSwitch("signin")}
              className="mt-6 w-full rounded-ctl bg-ink py-3 text-sm font-medium uppercase tracking-[0.12em] text-paper transition-opacity hover:opacity-90"
            >
              Go to sign in
            </button>
          </>
        ) : (
          <>
            <p className="label mb-3 text-muted">{isSignup ? "New diary" : "Welcome back"}</p>
            <h2 className="display text-3xl leading-tight">
              {isSignup ? "Start your diary." : "Sign in."}
            </h2>
            <p className="mt-3 text-[15px] leading-relaxed text-muted">
              {isSignup
                ? "An email and a password — that's it. Tonight's square is waiting on the other side."
                : "Pick up where you left off."}
            </p>

            <form onSubmit={submit} className="mt-6 space-y-4">
              {isSignup && (
                <Field label="Name" value={name} onChange={setName} placeholder="What should we call you?" autoFocus />
              )}
              <Field
                label="Email"
                type="email"
                value={email}
                onChange={setEmail}
                placeholder="you@email.com"
                autoFocus={!isSignup}
                required
              />
              <Field
                label="Password"
                type="password"
                value={password}
                onChange={setPassword}
                placeholder={isSignup ? "At least 6 characters" : "Your password"}
                required
              />

              {error && <p className="text-sm text-accent">{error}</p>}

              <button
                type="submit"
                disabled={busy || !email.trim() || password.length < 6}
                className="w-full rounded-ctl bg-ink py-3 text-sm font-medium uppercase tracking-[0.12em] text-paper transition-opacity hover:opacity-90 disabled:opacity-40"
              >
                {busy ? "…" : isSignup ? "Start my diary" : "Sign in"}
              </button>
            </form>

            {/* forgot password — sign-in only */}
            {!isSignup &&
              (resetSent ? (
                <p className="mt-3 text-center text-xs text-muted">
                  Reset link sent to <span className="text-ink">{email}</span> — check your inbox.
                </p>
              ) : (
                <button
                  type="button"
                  onClick={forgot}
                  disabled={busy}
                  className="mt-3 w-full text-center text-xs text-muted transition-colors hover:text-ink disabled:opacity-40"
                >
                  Forgot password?
                </button>
              ))}

            <button
              onClick={() => {
                setError(null);
                onSwitch(isSignup ? "signin" : "signup");
              }}
              className="mt-4 w-full text-center text-xs text-muted transition-colors hover:text-ink"
            >
              {isSignup ? "Already have a diary? Sign in" : "New here? Create a diary"}
            </button>
          </>
        )}
      </div>
    </div>
  );
}

function Field({
  label,
  value,
  onChange,
  placeholder,
  type = "text",
  autoFocus,
  required,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  type?: string;
  autoFocus?: boolean;
  required?: boolean;
}) {
  return (
    <label className="block">
      <span className="label mb-1.5 block text-muted">{label}</span>
      <input
        autoFocus={autoFocus}
        required={required}
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="w-full border-b border-line-strong bg-transparent pb-2 text-[15px] outline-none placeholder:text-faint focus:border-ink"
      />
    </label>
  );
}
