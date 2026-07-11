"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { useEntries } from "@/lib/store";
import { signIn, signUp } from "@/lib/profile";
import { countsByDate, recentDrinks, recentMoods } from "@/lib/derive";
import { addMonths } from "@/lib/date";
import { MonthCalendar } from "../calendar/MonthCalendar";
import { LogSheet } from "../log/LogSheet";
import { ThemeToggle } from "../ui/ThemeToggle";

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
          <ThemeToggle />
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
        {entries.length === 0 && (
          <p className="mt-8 text-center text-sm text-faint">
            Tap any day to log your first drink. No account needed yet.
          </p>
        )}
      </section>

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
  const router = useRouter();

  const isSignup = mode === "signup";

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
      <button aria-label="Close" className="absolute inset-0 bg-ink/40 backdrop-blur-sm" onClick={onClose} />
      <div className="glass-strong animate-sheet relative w-full max-w-md rounded-t-[28px] p-6 sm:rounded-[28px] sm:p-8">
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
            <p className="label mb-3 text-faint">
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

            <button
              onClick={() => {
                setError(null);
                onSwitch(isSignup ? "signin" : "signup");
              }}
              className="mt-4 w-full text-center text-xs text-faint transition-colors hover:text-ink"
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
      <span className="label mb-1.5 block text-faint">{label}</span>
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
