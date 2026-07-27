"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEntries } from "@/lib/store";
import { signIn, signUp, sendPasswordReset } from "@/lib/profile";
import { countsByDate, recentDrinks, recentMoods } from "@/lib/derive";
import { addMonths } from "@/lib/date";
import { MonthCalendar } from "../calendar/MonthCalendar";
import { LogSheet } from "../log/LogSheet";
import { useParallax } from "../ui/useParallax";

type AuthMode = "signup" | "signin";

/**
 * The logged-out intro.
 *
 * HOW IT'S BUILT — one client component, no route of its own: `app/page.tsx` reads the
 * session cookie on the SERVER and renders either `CalendarHome` or this. So the visitor's
 * first paint is the real landing, never a flash of app chrome.
 *
 * WHAT INSPIRED THE STRUCTURE — "experience first, register at the moment of value"
 * (Duolingo's lesson-before-signup, Figma's live file). The page introduces the app in a
 * narrative order and puts the REAL calendar a third of the way down, not at the bottom:
 *
 *   hero → the mosaic it becomes → how it works → TRY IT (live, no account)
 *        → the Passport (why people stay) → what's inside → where you can get it
 *        → the line we don't cross → sign up
 *
 * The platform block is deliberately INERT TEXT, not buttons. brewdiary is a web app today;
 * a disabled-looking App Store badge that does nothing is a small lie and a dead tap target.
 * Stating "in the works" in plain type is honest and costs the visitor nothing.
 */
export function Landing() {
  const entries = useEntries();
  const counts = countsByDate(entries);
  const now = new Date();

  const [cursor, setCursor] = useState({ y: now.getFullYear(), m: now.getMonth() });
  const [selected, setSelected] = useState<string | null>(null);
  const [authMode, setAuthMode] = useState<AuthMode | null>(null);
  const autoOpened = useRef(false);

  const canNext =
    cursor.y < now.getFullYear() || (cursor.y === now.getFullYear() && cursor.m < now.getMonth());

  const dayEntries = selected
    ? entries.filter((e) => e.date === selected).sort((a, b) => a.createdAt.localeCompare(b.createdAt))
    : [];

  // Once something's logged and the sheet is closed, open the sign-up sheet once.
  const askToRegister = entries.length > 0 && !selected;
  useEffect(() => {
    if (askToRegister && !autoOpened.current) {
      autoOpened.current = true;
      setAuthMode("signup");
    }
  }, [askToRegister]);

  function step(delta: number) {
    setCursor((c) => {
      const d = addMonths(new Date(c.y, c.m, 1), delta);
      return { y: d.getFullYear(), m: d.getMonth() };
    });
  }

  // The single conversion action, shared by every CTA on the page. Taking any CTA
  // counts as the ask, so the post-log auto-pop doesn't fire on top of it.
  const openSignup = () => {
    autoOpened.current = true;
    setAuthMode("signup");
  };

  return (
    <>
      {/* Registration is ALWAYS one tap away — a persistent CTA that follows the reader down. */}
      <header className="sticky top-0 z-30 -mx-5 mb-9 flex items-center justify-between gap-3 border-b border-line/60 bg-canvas/75 px-5 py-3 backdrop-blur-xl">
        <span className="font-display text-lg italic text-muted">brewdiary</span>
        <div className="flex items-center gap-1.5">
          <button
            type="button"
            onClick={() => setAuthMode("signin")}
            className="rounded-ctl px-3 py-2 text-xs font-medium uppercase tracking-[0.12em] text-muted transition-colors hover:text-ink"
          >
            Sign in
          </button>
          <button
            type="button"
            onClick={openSignup}
            className="rounded-ctl bg-ink px-4 py-2 text-xs font-medium uppercase tracking-[0.12em] text-paper transition-transform duration-150 ease-out hover:opacity-90 active:scale-[0.98]"
          >
            Create diary
          </button>
        </div>
      </header>

      <Hero onStart={openSignup} />

      {/* The artefact you're being offered, immediately after the promise. */}
      <YearPreview />

      <HowItWorks />

      {/* Moved UP from the foot of the page: the live diary is the strongest argument
          on the page, and an argument you can't reach doesn't convert anyone. */}
      <TryIt
        counts={counts}
        cursor={cursor}
        canNext={canNext}
        logged={entries.length}
        onSelect={setSelected}
        onStep={step}
      />

      {/* The reason people STAY — the gamified Passport (a map of your taste). */}
      <PassportTeaser />

      <Inside />

      {/* Where you can actually get it. Honest, inert, no fake store badges. */}
      <Platforms onStart={openSignup} />

      {/* The product's spine, said out loud. */}
      <Promise />

      <ClosingCTA loggedCount={entries.length} onStart={openSignup} />

      <Footer />

      {selected && (
        <LogSheet
          dateKey={selected}
          dayEntries={dayEntries}
          recentDrinks={recentDrinks(entries)}
          recentMoods={recentMoods(entries)}
          onClose={() => setSelected(null)}
        />
      )}

      {authMode && (
        <AuthSheet
          mode={authMode}
          loggedCount={entries.length}
          onSwitch={(m) => setAuthMode(m)}
          onClose={() => setAuthMode(null)}
        />
      )}
    </>
  );
}

// ─── Hero ────────────────────────────────────────────────────────────────────
// One value prop, one CTA, and the platform truth stated in the same breath so
// nobody scrolls the whole page wondering where the app store link is.
function Hero({ onStart }: { onStart: () => void }) {
  return (
    <section className="mb-12">
      <p className="label mb-4 text-faint">The all-inclusive drink diary</p>
      <h1 className="display leading-[0.95]">
        Every night
        <br />
        gets a square.
      </h1>
      <p className="mt-6 max-w-md text-[15px] leading-relaxed text-muted">
        Coffee, wine, a midnight kombucha — whatever you poured. Tap a day, log it in a breath,
        and watch a year of habits fill into a quiet mosaic you&apos;ll want to keep.
      </p>
      <div className="mt-7 flex flex-col gap-3 sm:flex-row sm:items-center">
        <button
          type="button"
          onClick={onStart}
          className="rounded-ctl bg-accent px-8 py-3.5 text-center text-sm font-medium uppercase tracking-[0.12em] text-accent-contrast shadow-[0_8px_28px_-8px_var(--accent),inset_0_1px_0_rgba(255,255,255,0.28)] transition-transform duration-150 ease-out hover:-translate-y-px active:translate-y-0"
        >
          Start your diary — free
        </button>
        <p className="text-xs leading-relaxed text-faint">Free · no card · 30 seconds · private by default</p>
      </div>
      <p className="mt-6 border-t border-line/70 pt-4 text-xs leading-relaxed text-faint">
        Runs in your browser, on any phone or laptop. Native iPhone and Android apps are in the works.
      </p>
    </section>
  );
}

// ─── The mosaic preview ──────────────────────────────────────────────────────
// A decorative, deterministic mosaic — "what your year becomes." Clearly a preview,
// never the visitor's data. Deterministic so SSR and client render identically.
function YearPreview() {
  const drift = useParallax<HTMLDivElement>();
  const COLS = 26;
  const ROWS = 7;
  const cells = Array.from({ length: COLS * ROWS }, (_, i) => {
    const n = (i * 2654435761) >>> 0; // cheap stable hash
    const r = (n % 100) / 100;
    if (r < 0.34) return 0;
    if (r < 0.62) return 1;
    if (r < 0.82) return 2;
    if (r < 0.94) return 3;
    return 4;
  });

  return (
    <section aria-hidden className="select-none">
      <div
        ref={drift}
        className="grid gap-1"
        style={{ gridTemplateColumns: `repeat(${COLS}, minmax(0, 1fr))` }}
      >
        {cells.map((level, i) => (
          <span
            key={i}
            className="aspect-square rounded-xs"
            style={{
              backgroundColor: level === 0 ? "var(--line)" : `var(--ycell-${level})`,
            }}
          />
        ))}
      </div>
      <p className="label mt-3 text-faint">A year of nights — darker is more</p>
    </section>
  );
}

// ─── How it works ────────────────────────────────────────────────────────────
// The mechanic in three beats. A visitor should know exactly what they're being
// asked to do before they're asked to do it (below, live).
const STEPS: { n: string; title: string; body: string }[] = [
  {
    n: "01",
    title: "Tap a day",
    body: "The home is a calendar, not a feed. The day you're on is already waiting.",
  },
  {
    n: "02",
    title: "Say what you poured",
    body: "A name, how it felt, a note or photo if you want. Five fields, most of them optional.",
  },
  {
    n: "03",
    title: "Watch the square darken",
    body: "That's the whole ritual. Two nights in and the grid starts to look like yours.",
  },
];

function HowItWorks() {
  return (
    <section className="mt-20">
      <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
        Ten seconds
        <br />
        a night.
      </h2>
      <div className="mt-9 grid gap-8 sm:grid-cols-3 sm:gap-6">
        {STEPS.map(({ n, title, body }) => (
          <div key={n} className="border-t border-line pt-4">
            <span aria-hidden className="label tnum text-accent">
              {n}
            </span>
            <h3 className="mt-2 font-display text-lg text-ink">{title}</h3>
            <p className="mt-1.5 text-[15px] leading-relaxed text-muted">{body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

// ─── Try it, for real ────────────────────────────────────────────────────────
function TryIt({
  counts,
  cursor,
  canNext,
  logged,
  onSelect,
  onStep,
}: {
  counts: Map<string, number>;
  cursor: { y: number; m: number };
  canNext: boolean;
  logged: number;
  onSelect: (d: string) => void;
  onStep: (delta: number) => void;
}) {
  return (
    <section className="mt-20">
      <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
        Tap a day.
        <br />
        Feel it fill.
      </h2>
      <p className="mb-7 mt-5 max-w-md text-[15px] leading-relaxed text-muted">
        This calendar is live — no account, nothing to install. Log one right here and your first
        square darkens. When you like it, make a diary and everything comes with you.
      </p>
      <MonthCalendar
        year={cursor.y}
        month={cursor.m}
        counts={counts}
        onSelect={onSelect}
        onPrev={() => onStep(-1)}
        onNext={() => onStep(1)}
        canNext={canNext}
      />
      <p className="mt-8 text-center text-sm text-faint">
        {logged === 0
          ? "Tap any day to log your first drink. No account needed yet."
          : "Saved on this device. Make a diary and it follows you to every screen you use."}
      </p>
    </section>
  );
}

// ─── The Passport ────────────────────────────────────────────────────────────
// A static, decorative version of the real Journey road (a winding path of landmarks
// you travel by trying NEW things, never by volume). Deterministic SVG so SSR and
// client render identically; travelled part gold, the road ahead dim and dashed,
// "you are here" glowing at the frontier.
function PassportTeaser() {
  const W = 640;
  const H = 120;
  const roadY = (x: number) => H / 2 + Math.sin((x / W) * Math.PI * 2.2) * 34;
  const pts = Array.from({ length: 81 }, (_, i) => {
    const x = (i / 80) * W;
    return `${x.toFixed(1)},${roadY(x).toFixed(1)}`;
  });
  const path = `M ${pts.join(" L ")}`;
  // 7 landmarks along the road; the first 3 are "reached" in the preview.
  const marks = [0.06, 0.2, 0.36, 0.52, 0.67, 0.82, 0.95].map((t, i) => ({
    x: t * W,
    y: roadY(t * W),
    reached: i < 3,
  }));
  const frontier = marks[2];

  return (
    <section className="mt-20">
      <p className="label mb-4 text-faint">The Passport</p>
      <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
        Every new pour
        <br />
        is a landmark.
      </h2>
      <p className="mt-6 max-w-md text-[15px] leading-relaxed text-muted">
        Your diary quietly draws a map of your taste. Try a drink you&apos;ve never had — a
        world opens. Meet a drink the dictionary doesn&apos;t know and you can chart it yourself.
        A dry day counts too. Nothing here rewards drinking more, only wandering wider.
      </p>

      <div aria-hidden className="glass mt-8 select-none overflow-hidden rounded-tile px-2 py-4">
        <svg viewBox={`0 0 ${W} ${H}`} className="w-full" role="presentation">
          {/* the road ahead — dim, dashed */}
          <path d={path} fill="none" stroke="var(--line-strong)" strokeWidth="2" strokeDasharray="6 7" />
          {/* travelled — gold, up to the frontier */}
          <path
            d={path}
            fill="none"
            stroke="var(--accent)"
            strokeWidth="2.5"
            strokeLinecap="round"
            pathLength={100}
            strokeDasharray="52 100"
          />
          {marks.map((m, i) => (
            <circle
              key={i}
              cx={m.x}
              cy={m.y}
              r={m.reached ? 6 : 4.5}
              fill={m.reached ? "var(--accent)" : "var(--glass-strong)"}
              stroke={m.reached ? "var(--accent)" : "var(--line-strong)"}
              strokeWidth="1.5"
            />
          ))}
          {/* you are here */}
          <circle cx={frontier.x} cy={frontier.y} r="11" fill="var(--accent)" opacity="0.22" />
          <circle cx={frontier.x} cy={frontier.y} r="6" fill="var(--accent)" />
        </svg>
        <p className="label mt-2 text-center text-faint">you are here — the road only asks for something new</p>
      </div>

      <p className="mt-5 max-w-md text-[15px] leading-relaxed text-muted">
        The map keeps a lifetime score built from two things only: how wide you&apos;ve
        wandered and how steadily you&apos;ve kept the diary. There is no axis for volume,
        and there is no leaderboard.
      </p>
    </section>
  );
}

// ─── What's inside ───────────────────────────────────────────────────────────
// A ledger, not a grid of feature cards — every line here is a screen that already
// exists behind the sign-up. Nothing aspirational is listed.
const LEDGER: { title: string; body: string }[] = [
  {
    title: "Streaks that survive a bad week",
    body: "Log a night, keep the run — and a dry day keeps it too. One missed day is forgiven, so a slip doesn’t wipe a month.",
  },
  {
    title: "Your year, counted",
    body: "What you poured most, your longest run, the words you keep reaching for. All read back from your entries — nothing to fill in twice.",
  },
  {
    title: "Together, not a feed",
    body: "Share a single pour with friends, a private circle, or the party you’re at. Cheers and comments, no audience to perform for.",
  },
  {
    title: "Settle the round",
    body: "Add a tab, add who was there, and the split falls out. Who paid, who owes, done at the table.",
  },
  {
    title: "Ninkasi, behind the bar",
    body: "Ask what to pour next. She reads your diary and your friends’ shared pours, not a catalogue of sponsored bottles.",
  },
  {
    title: "Gentle limits, if you want them",
    body: "Set a weekly number or a couple of dry days and the diary quietly keeps track. Off by default, yours to switch off again.",
  },
  {
    title: "Four looks, one diary",
    body: "Light, Dark, a hand-drawn Sketchbook, and a warm Espresso. Pick the one that feels like your notebook — it’s one tap in Settings.",
  },
];

function Inside() {
  return (
    <section className="mt-20">
      <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
        One tap a night.
        <br />
        It adds up.
      </h2>

      <ol className="mt-8 divide-y divide-line">
        {LEDGER.map(({ title, body }, i) => (
          <li key={title} className="grid grid-cols-[2.25rem_1fr] gap-x-3 py-5 sm:gap-x-5">
            <span aria-hidden className="label tnum pt-1 text-faint">
              {String(i + 1).padStart(2, "0")}
            </span>
            <div>
              <h3 className="font-display text-lg text-ink">{title}</h3>
              <p className="mt-1.5 max-w-md text-[15px] leading-relaxed text-muted">{body}</p>
            </div>
          </li>
        ))}
      </ol>
    </section>
  );
}

// ─── Where you can get it ────────────────────────────────────────────────────
// DELIBERATELY NOT BUTTONS. brewdiary ships as a web app today; the phone builds
// aren't out. A greyed-out store badge is a dead tap target and a small lie, so
// the two unreleased rows are plain text with a "soon" marker and no affordance —
// nothing here is focusable, hoverable, or clickable. The only real action in this
// section is the one real action we have: make a diary in the browser.
const PLATFORMS: { name: string; note: string; ready: boolean }[] = [
  {
    name: "Web",
    note: "Available now — works in any browser, phone or laptop, and syncs across both.",
    ready: true,
  },
  {
    name: "iPhone",
    note: "In the works. Until then, open brewdiary in Safari, tap Share, then Add to Home Screen — it opens full-screen like an app.",
    ready: false,
  },
  {
    name: "Android",
    note: "In the works. Until then, open brewdiary in Chrome, tap the menu, then Add to Home screen.",
    ready: false,
  },
];

function Platforms({ onStart }: { onStart: () => void }) {
  return (
    <section className="mt-20">
      <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
        No download.
        <br />
        Not yet, anyway.
      </h2>
      <p className="mt-6 max-w-md text-[15px] leading-relaxed text-muted">
        brewdiary lives on the web today, so there&apos;s nothing to install and nothing to
        update. The App Store and Play Store builds are being made — when they land, your diary
        will already be in them.
      </p>

      <ul className="mt-8 divide-y divide-line">
        {PLATFORMS.map(({ name, note, ready }) => (
          <li key={name} className="flex flex-col gap-1 py-5 sm:flex-row sm:items-baseline sm:gap-6">
            <div className="flex w-32 shrink-0 items-baseline gap-2.5">
              <span className="font-display text-lg text-ink">{name}</span>
              <span
                className={
                  ready
                    ? "label text-accent"
                    : "label rounded-xs border border-line-strong px-1.5 py-0.5 text-[0.625rem] text-faint"
                }
              >
                {ready ? "Live" : "Soon"}
              </span>
            </div>
            <p className="max-w-md text-[15px] leading-relaxed text-muted">{note}</p>
          </li>
        ))}
      </ul>

      <button
        type="button"
        onClick={onStart}
        className="mt-8 w-full rounded-ctl border border-line-strong py-3.5 text-sm font-medium uppercase tracking-[0.12em] text-ink transition-colors duration-150 hover:bg-ink hover:text-paper active:scale-[0.985] sm:w-auto sm:px-10"
      >
        Open it in this browser
      </button>
    </section>
  );
}

// ─── The line ────────────────────────────────────────────────────────────────
// The product's spine. It belongs on the landing page because it is the actual
// difference between this and every other tracker — and because saying it in
// public is what keeps us honest about it.
function Promise() {
  return (
    <section className="mt-20">
      <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
        Nothing here
        <br />
        rewards drinking
        <br />
        more.
      </h2>
      <div className="mt-8 space-y-5 border-l border-accent/50 pl-5">
        <p className="max-w-md text-[15px] leading-relaxed text-muted">
          Every count in the app is a count of <span className="text-ink">variety</span> — a drink
          you&apos;ve never had, a place you&apos;ve never been, a night you had water instead. A dry
          day keeps your streak. There is no total-drinks leaderboard, because we will not build the
          scoreboard you win by pouring one more.
        </p>
        <p className="max-w-md text-[15px] leading-relaxed text-muted">
          Every entry starts <span className="text-ink">private on your device</span>. Sharing is a
          separate tap, always after the fact. You can export everything you&apos;ve ever written, or
          delete the account and take it all with you, from one screen in Settings.
        </p>
        <p className="max-w-md text-[15px] leading-relaxed text-muted">
          It&apos;s a diary for whatever you drink — the espresso at seven, the beer at nine, the
          kombucha you keep meaning to finish. If you don&apos;t drink alcohol at all, the app still
          works exactly the same.
        </p>
      </div>
    </section>
  );
}

function ClosingCTA({ loggedCount, onStart }: { loggedCount: number; onStart: () => void }) {
  const started = loggedCount > 0;

  return (
    <section className="glass mt-16 rounded-tile p-6 sm:p-8">
      <h2 className="display text-[2.25rem] leading-[1.05] sm:text-[2.75rem]">
        {started ? "Keep what you logged." : "Start tonight."}
      </h2>
      <p className="mt-4 max-w-md text-[15px] leading-relaxed text-muted">
        {started
          ? "Your entries live on this device until you make a diary. Sign up and they come with you — phone, laptop, next year."
          : "A diary takes an email and a password. Free, no card, and the first square is one tap away."}
      </p>
      <button
        type="button"
        onClick={onStart}
        className="mt-7 w-full rounded-ctl bg-accent py-3.5 text-sm font-medium uppercase tracking-[0.12em] text-accent-contrast shadow-[0_8px_28px_-8px_var(--accent),inset_0_1px_0_rgba(255,255,255,0.28)] transition-transform duration-150 ease-out hover:-translate-y-px active:translate-y-0 sm:w-auto sm:px-10"
      >
        Create a diary
      </button>
      <p className="mt-4 text-xs text-faint">Free · no card · private by default · nothing to install</p>
    </section>
  );
}

function Footer() {
  return (
    <footer className="mt-16 flex flex-col gap-3 border-t border-line pt-6 text-xs text-faint sm:flex-row sm:items-center sm:justify-between">
      <span className="font-display text-base italic text-muted">brewdiary</span>
      <div className="flex items-center gap-5">
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

function AuthSheet({
  mode,
  loggedCount,
  onSwitch,
  onClose,
}: {
  mode: AuthMode;
  loggedCount: number;
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
            <p className="label mb-3 text-muted">
              {isSignup
                ? loggedCount > 0
                  ? loggedCount > 1
                    ? `${loggedCount} nights logged`
                    : "First night logged"
                  : "New diary"
                : "Welcome back"}
            </p>
            <h2 className="display text-3xl leading-tight">
              {isSignup ? "Keep your diary." : "Sign in."}
            </h2>
            <p className="mt-3 text-[15px] leading-relaxed text-muted">
              {isSignup
                ? "Save what you logged and start a streak. Email and a password — that's it."
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
