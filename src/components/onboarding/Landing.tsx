"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { useEntries } from "@/lib/store";
import { signIn, signUp, sendPasswordReset } from "@/lib/profile";
import { countsByDate, recentDrinks, recentMoods } from "@/lib/derive";
import { addMonths } from "@/lib/date";
import { MonthCalendar } from "../calendar/MonthCalendar";
import { LogSheet } from "../log/LogSheet";
import { useParallax } from "../ui/useParallax";

type AuthMode = "signup" | "signin";

// The logged-out intro. Swiss-minimal, but it embeds the *real* calendar so a
// first-time visitor actually logs a drink before being asked to register —
// "experience first, register at the moment of value."
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

  return (
    <>
      <header className="mb-10 flex items-center justify-between">
        <span className="font-display text-lg italic text-muted">brewdiary</span>
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={() => setAuthMode("signin")}
            className="rounded-ctl px-3 py-1.5 text-xs font-medium uppercase tracking-[0.12em] text-muted transition-colors hover:bg-ink/5 hover:text-ink"
          >
            Sign in
          </button>
        </div>
      </header>

      <section className="mb-12">
        <p className="label mb-4 text-faint">A drink diary</p>
        <h1 className="display leading-[0.95]">
          Every night
          <br />
          gets a square.
        </h1>
        <p className="mt-6 max-w-md text-[15px] leading-relaxed text-muted">
          Coffee, wine, a midnight kombucha — whatever you poured. Tap a day, log it in
          a breath, and watch the year quietly fill in.
        </p>
        <p className="mt-4 max-w-md text-[15px] leading-relaxed text-muted">
          The squares darken the more you drink, so a month of habits is one glance, not a
          spreadsheet. Keep it private, or pour with friends.
        </p>
      </section>

      <YearPreview />

      <section className="mt-12">
        <p className="label mb-5 text-faint">Try it — tap a day</p>
        <MonthCalendar
          year={cursor.y}
          month={cursor.m}
          counts={counts}
          onSelect={setSelected}
          onPrev={() => step(-1)}
          onNext={() => step(1)}
          canNext={canNext}
        />
        <p className="mt-8 text-center text-sm text-faint">
          {entries.length === 0
            ? "Tap any day to log your first drink. No account needed yet."
            : "Logged on this device. Make a diary below and it comes with you."}
        </p>
      </section>

      <PassportTeaser />

      <Ledger />

      <ClosingCTA
        loggedCount={entries.length}
        onStart={() => {
          autoOpened.current = true; // taking the CTA counts as the ask; don't auto-pop later
          setAuthMode("signup");
        }}
      />

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

// The Passport teaser — a static, decorative version of the real Journey road
// (a winding path of landmarks you travel by trying NEW things, never by volume).
// Deterministic SVG so SSR and client render identically; travelled part gold,
// the road ahead dim and dashed, "you are here" glowing at the frontier.
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
        world opens. A dry day counts too. Nothing here rewards drinking more, only
        wandering wider.
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
    </section>
  );
}

// What the diary actually gives you back. A ledger, not a grid of feature cards —
// every line here is a screen that already exists behind the sign-up.
const LEDGER: { title: string; body: string }[] = [
  {
    title: "Streaks that survive a bad week",
    body: "Log a night, keep the run. One missed day is forgiven, so a slip doesn’t wipe a month. Seven, thirty, a hundred — the meter fills as you go.",
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
    title: "Private until you say otherwise",
    body: "Every entry starts private on your device. Sharing is a separate tap, always after the fact.",
  },
  {
    title: "Four looks, one diary",
    body: "Light, Dark, a hand-drawn Sketchbook, and a warm Espresso. Pick the one that feels like your notebook — it's in Settings, one tap.",
  },
];

function Ledger() {
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
        className="mt-7 w-full rounded-ctl bg-ink py-3.5 text-sm font-medium uppercase tracking-[0.12em] text-paper transition-transform duration-150 ease-out hover:opacity-90 active:scale-[0.985] sm:w-auto sm:px-10"
      >
        Create a diary
      </button>
      <p className="mt-4 text-xs text-faint">
        Free · no card · private by default · works offline as an app
      </p>
    </section>
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
