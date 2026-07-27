"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { signIn, signUp, sendPasswordReset } from "@/lib/profile";
import { useParallax } from "../ui/useParallax";

type AuthMode = "signup" | "signin";

/**
 * The logged-out landing page.
 *
 * HOW IT'S BUILT — one client component, no route of its own: `app/page.tsx` reads the
 * session cookie on the SERVER and renders either `CalendarHome` or this. So a visitor's
 * first paint is the real landing and a returning diarist's is the real app — no flash
 * of the wrong thing, no client-side redirect.
 *
 * WHAT IT DELIBERATELY IS NOT — a demo. An earlier version embedded the live calendar and
 * the log sheet so a stranger could log a drink before registering. That is gone by choice:
 * the app's screens (the calendar, the Passport, Together) are now what you get AFTER you
 * make a diary, and this page's only job is to make the case and take the sign-up. Nothing
 * here reads or writes an entry, so there is no local diary to migrate and no half-state
 * where someone's nights live in a browser they'll never open again.
 *
 * WHAT INSPIRED THE SHAPE — the "one page, one argument, one action" long-form product page
 * (Linear, Arc, Things). Sections never repeat a layout: a hero, a mosaic band, three pillar
 * blocks, a drawn map, a ledger, a platform list, a promise, a close. The only tap targets on
 * the whole page are sign-in and create-diary.
 */
export function Landing() {
  const [authMode, setAuthMode] = useState<AuthMode | null>(null);
  const openSignup = () => setAuthMode("signup");

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
      <MosaicBand />
      <Pillars />
      <PassportTeaser onStart={openSignup} />
      <Ledger />
      <Platforms onStart={openSignup} />
      <Promise />
      <ClosingCTA onStart={openSignup} />
      <Footer />

      {authMode && (
        <AuthSheet mode={authMode} onSwitch={(m) => setAuthMode(m)} onClose={() => setAuthMode(null)} />
      )}
    </>
  );
}

// ─── Hero ────────────────────────────────────────────────────────────────────
// One promise, one action, and the platform truth in the same breath so nobody
// scrolls the whole page hunting for an app-store link that isn't there yet.
function Hero({ onStart }: { onStart: () => void }) {
  return (
    <section className="mb-14">
      <p className="label mb-4 text-faint">The all-inclusive drink diary</p>
      <h1 className="display leading-[0.95]">
        Every night
        <br />
        gets a square.
      </h1>
      <p className="mt-6 max-w-md text-[15px] leading-relaxed text-muted">
        Coffee, wine, a homebrew, a midnight kombucha — whatever you poured, it takes one tap to
        keep. A year later you&apos;re holding a mosaic of your own taste, and it tells you
        something no photo roll ever did.
      </p>
      <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:items-center">
        <button
          type="button"
          onClick={onStart}
          className="rounded-ctl bg-accent px-8 py-3.5 text-center text-sm font-medium uppercase tracking-[0.12em] text-accent-contrast shadow-[0_8px_28px_-8px_var(--accent),inset_0_1px_0_rgba(255,255,255,0.28)] transition-transform duration-150 ease-out hover:-translate-y-px active:translate-y-0"
        >
          Start your diary — free
        </button>
        <p className="text-xs leading-relaxed text-faint">Free · no card · 30 seconds · private by default</p>
      </div>
      <p className="mt-8 border-t border-line/70 pt-4 text-xs leading-relaxed text-faint">
        Runs in your browser, on any phone or laptop, and syncs across both. Native iPhone and
        Android apps are in the works.
      </p>
    </section>
  );
}

// ─── The mosaic band ─────────────────────────────────────────────────────────
// Decorative and deterministic — "what your year becomes." Never a real calendar,
// never anyone's data; the same hash renders on the server and the client so
// there's no hydration mismatch.
function MosaicBand() {
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
            style={{ backgroundColor: level === 0 ? "var(--line)" : `var(--ycell-${level})` }}
          />
        ))}
      </div>
      <p className="label mt-3 text-faint">A year of nights — brighter is more</p>
    </section>
  );
}

// ─── The three pillars ───────────────────────────────────────────────────────
// The whole argument in three blocks. Stacked and full-width rather than a row of
// equal cards — a three-card grid is the tell that nobody decided what matters most.
const PILLARS: { kicker: string; title: string; body: string }[] = [
  {
    kicker: "The ritual",
    title: "One tap, then it’s out of your way.",
    body: "Name it, mark how it felt, add a note or a photo if the night deserves one. That’s the whole thing. No macros, no units, no forms that make you feel audited — a diary you’ll still be keeping in March.",
  },
  {
    kicker: "The collection",
    title: "A streak you can actually hold.",
    body: "Every logged night brightens a square, and the grid becomes the object: your year, at a glance, unmistakably yours. Miss a day and the run survives — one slip is forgiven, so a bad week never wipes a month. A day you drank nothing counts too.",
  },
  {
    kicker: "The map",
    title: "It learns your taste and shows you the edges of it.",
    body: "Everything you log folds into families — the stouts, the sours, the single-origins — and what comes back is a map with borders. You can see what you keep returning to, and exactly where you’ve never been.",
  },
];

function Pillars() {
  return (
    <section className="mt-20">
      <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
        A notes app
        <br />
        can’t do this.
      </h2>
      <div className="mt-10 space-y-10">
        {PILLARS.map(({ kicker, title, body }) => (
          <article key={kicker} className="border-t border-line pt-5">
            <p className="label text-accent">{kicker}</p>
            <h3 className="mt-3 font-display text-2xl leading-snug text-ink sm:text-[1.75rem]">{title}</h3>
            <p className="mt-3 max-w-lg text-[15px] leading-relaxed text-muted">{body}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

// ─── The Passport ────────────────────────────────────────────────────────────
// A static, decorative rendering of the real Journey road (a winding path of landmarks
// you travel by trying NEW things, never by volume). Deterministic SVG so SSR and client
// agree; travelled part gold, road ahead dim and dashed, "you are here" at the frontier.
function PassportTeaser({ onStart }: { onStart: () => void }) {
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
      <p className="mt-6 max-w-lg text-[15px] leading-relaxed text-muted">
        Your diary draws a road, and you travel it by trying something you&apos;ve never had.
        Order a wine you can&apos;t pronounce and a new region opens. Meet a drink our dictionary
        has never heard of and you can chart it yourself — name it, place it, and it&apos;s on the
        map for everyone who comes after you.
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

      <p className="mt-6 max-w-lg text-[15px] leading-relaxed text-muted">
        There&apos;s a lifetime score on the map, and it&apos;s built from exactly two things: how
        wide you&apos;ve wandered and how steadily you&apos;ve kept the diary. No axis for volume.
        No table of who drank most. Ever.
      </p>

      <button
        type="button"
        onClick={onStart}
        className="mt-8 w-full rounded-ctl border border-line-strong py-3.5 text-sm font-medium uppercase tracking-[0.12em] text-ink transition-colors duration-150 hover:bg-ink hover:text-paper active:scale-[0.985] sm:w-auto sm:px-10"
      >
        Start my map
      </button>
    </section>
  );
}

// ─── The rest ────────────────────────────────────────────────────────────────
// A ledger, not a wall of feature cards. Every line is a thing that exists behind
// the sign-up — nothing aspirational is listed here.
const LEDGER: { title: string; body: string }[] = [
  {
    title: "Share one pour, not your life",
    body: "Send a single entry to a friend, a private circle, or the table you’re sitting at. Cheers and comments come back. There’s no infinite feed and no audience to perform for, because the diary is the point and the sharing is the afterthought.",
  },
  {
    title: "Settle the round at the table",
    body: "Add the tab, add who was there, and the split falls out — who paid, who owes, cleared before anyone’s put their card away.",
  },
  {
    title: "The night, not just the drink",
    body: "Start a party or a plan, pull the people who are actually there into it, and the whole evening lands in everyone’s diary at once instead of being retyped five times.",
  },
  {
    title: "Bars that know you, without a file on you",
    body: "Walk into a partner bar and a loyalty card fills itself — earned in place, punched by staff, never by you. What the bar sees is the nights it served you. Your diary never crosses the counter.",
  },
  {
    title: "Your words, given back",
    body: "The drink you reach for most, your longest run, the adjectives you use without noticing. All of it read back out of what you already wrote — there is never a second form to fill in.",
  },
  {
    title: "Quiet limits, only if you ask",
    body: "Pick a weekly number or a couple of dry days and the diary keeps count without a word. Off by default, and off again the moment you want it off.",
  },
  {
    title: "Four looks, one diary",
    body: "Light, Dark, a hand-drawn Sketchbook, and a warm Espresso. Pick the one that feels like your notebook — it’s one tap, and it sticks.",
  },
];

function Ledger() {
  return (
    <section className="mt-20">
      <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
        And then
        <br />
        there’s the rest.
      </h2>

      <ol className="mt-8 divide-y divide-line">
        {LEDGER.map(({ title, body }, i) => (
          <li key={title} className="grid grid-cols-[2.25rem_1fr] gap-x-3 py-5 sm:gap-x-5">
            <span aria-hidden className="label tnum pt-1 text-faint">
              {String(i + 1).padStart(2, "0")}
            </span>
            <div>
              <h3 className="font-display text-lg text-ink">{title}</h3>
              <p className="mt-1.5 max-w-lg text-[15px] leading-relaxed text-muted">{body}</p>
            </div>
          </li>
        ))}
      </ol>
    </section>
  );
}

// ─── Where you can get it ────────────────────────────────────────────────────
// DELIBERATELY NOT BUTTONS. brewdiary ships as a web app today; the phone builds
// aren't out. A greyed-out store badge is a dead tap target and a small lie, so the
// two unreleased rows are plain text with a "soon" marker and no affordance at all —
// nothing here is focusable, hoverable, or clickable. The only real action in this
// section is the only real action we have: make a diary in this browser.
const PLATFORMS: { name: string; note: string; ready: boolean }[] = [
  {
    name: "Web",
    note: "Available now. Works in any browser on any device, and your diary follows you between them.",
    ready: true,
  },
  {
    name: "iPhone",
    note: "In the works. Until then: open brewdiary in Safari, tap Share, then Add to Home Screen — it opens full-screen, like an app.",
    ready: false,
  },
  {
    name: "Android",
    note: "In the works. Until then: open brewdiary in Chrome, tap the menu, then Add to Home screen.",
    ready: false,
  },
];

function Platforms({ onStart }: { onStart: () => void }) {
  return (
    <section className="mt-20">
      <h2 className="display text-[2.5rem] leading-[1.05] sm:text-5xl">
        Nothing
        <br />
        to download.
      </h2>
      <p className="mt-6 max-w-lg text-[15px] leading-relaxed text-muted">
        brewdiary lives on the web, so there&apos;s no install and no update to sit through. The
        App Store and Play Store builds are being made — when they land, your diary will already
        be inside them.
      </p>

      <ul className="mt-8 divide-y divide-line">
        {PLATFORMS.map(({ name, note, ready }) => (
          <li key={name} className="flex flex-col gap-1.5 py-5 sm:flex-row sm:items-baseline sm:gap-6">
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
// The product's spine, said in public. It's the actual difference between this and
// every other tracker, and printing it on the landing page is what keeps us to it.
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
        <p className="max-w-lg text-[15px] leading-relaxed text-muted">
          Every count in the app counts <span className="text-ink">variety</span> — a drink
          you&apos;ve never had, a place you&apos;ve never been, a night you had water instead. A
          dry day keeps your streak. There is no total-drinks leaderboard, and there never will
          be, because that&apos;s a scoreboard you win by pouring one more.
        </p>
        <p className="max-w-lg text-[15px] leading-relaxed text-muted">
          Every entry starts <span className="text-ink">private</span>. Sharing is a separate tap,
          always after the fact, always one entry at a time. Export everything you&apos;ve ever
          written, or delete the account and take it all with you — one screen, no email to
          support, no retention offer.
        </p>
        <p className="max-w-lg text-[15px] leading-relaxed text-muted">
          And it&apos;s a diary for whatever you drink — the espresso at seven, the beer at nine,
          the kombucha you keep meaning to finish. If you don&apos;t drink alcohol at all, the app
          works exactly the same.
        </p>
      </div>
    </section>
  );
}

function ClosingCTA({ onStart }: { onStart: () => void }) {
  return (
    <section className="glass mt-16 rounded-tile p-6 sm:p-8">
      <h2 className="display text-[2.25rem] leading-[1.05] sm:text-[2.75rem]">Start tonight.</h2>
      <p className="mt-4 max-w-md text-[15px] leading-relaxed text-muted">
        A diary takes an email and a password. Free, no card, and tonight&apos;s square is one tap
        away once you&apos;re in.
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
                ? "An email and a password — that's the whole sign-up. Tonight's square is waiting on the other side."
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
