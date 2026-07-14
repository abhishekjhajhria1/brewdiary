"use client";

import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { confirmAge, isAgeConfirmed, legalAgeFor } from "@/lib/age";
import { KNOWN_COUNTRIES } from "@/lib/jurisdiction";

// Pages that must be readable WITHOUT the gate. A privacy policy you can only see
// after asserting you're of drinking age is not a published privacy policy — and
// an app-store reviewer will be looking for exactly this.
const OPEN_PAGES = ["/privacy", "/terms"];

// Shown over everything on first visit until a valid date of birth is entered.
// Visibility is driven by the `needs-age` class on <html> (set flash-free by the
// inline script in layout.tsx) + CSS in globals.css, so it never flickers.
export function AgeGate() {
  const pathname = usePathname();
  const [state, setState] = useState<"gate" | "blocked" | "done">("gate");
  const [value, setValue] = useState("");
  const [country, setCountry] = useState("IN");
  const [error, setError] = useState<string | null>(null);
  // Computed AFTER mount, never during render: `new Date()` on the server and in
  // the browser can disagree (they straddle the UTC boundary), and that mismatch
  // breaks hydration — which left this form INERT, so submitting it did a native
  // GET, reloaded the page, and brought the gate straight back. A reload loop.
  const [today, setToday] = useState<string | undefined>(undefined);
  useEffect(() => setToday(new Date().toISOString().slice(0, 10)), []);

  // The bar isn't one number: 21 in the US, 20 in Japan, 19 in Korea, 18 in much of
  // Europe. We ask where you are and apply the real one.
  const required = legalAgeFor(country);

  useEffect(() => {
    if (isAgeConfirmed()) setState("done");
  }, []);

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!value) {
      setError("Please enter your date of birth.");
      return;
    }
    const dob = new Date(value + "T00:00:00");
    if (confirmAge(dob, country)) {
      document.documentElement.classList.remove("needs-age");
      setState("done");
    } else {
      setState("blocked");
    }
  }

  if (state === "done") return null;
  if (OPEN_PAGES.includes(pathname)) return null;

  return (
    <div className="age-gate fixed inset-0 z-60 flex items-center justify-center p-5">
      <div className="glass-strong w-full max-w-sm rounded-tile p-7 sm:p-8">
        <p className="font-display text-lg italic text-muted">brewdiary</p>

        {state === "blocked" ? (
          <>
            <h1 className="mt-4 font-display text-3xl leading-tight text-ink">Not just yet.</h1>
            <p className="mt-3 text-[15px] leading-relaxed text-muted">
              You need to be of legal drinking age where you are ({required}+) to use brewdiary. Come back when you
              are.
            </p>
            <button
              onClick={() => {
                setState("gate");
                setError(null);
              }}
              className="mt-6 text-sm text-faint transition-colors hover:text-ink"
            >
              Re-enter date
            </button>
          </>
        ) : (
          <>
            <h1 className="mt-4 font-display text-3xl leading-tight text-ink">A quick check.</h1>
            <p className="mt-3 text-[15px] leading-relaxed text-muted">
              brewdiary is a diary of what you drink — alcohol included. Confirm your date of birth to come in.
            </p>

            {/* action="#" + noValidate: if this form is ever inert again (a hydration
                break, a JS error, a slow bundle), a native submit must NOT navigate —
                that's what turned one bad render into an inescapable reload loop. */}
            <form onSubmit={submit} action="#" noValidate className="mt-6">
              <label className="mb-4 block">
                <span className="label mb-1.5 block text-faint">Where you are</span>
                <select
                  value={country}
                  onChange={(e) => setCountry(e.target.value)}
                  className="w-full border-b border-line-strong bg-transparent pb-2 text-[15px] focus:border-ink"
                >
                  {KNOWN_COUNTRIES.map((c) => (
                    <option key={c.code} value={c.code}>
                      {c.label}
                    </option>
                  ))}
                  <option value="ZZ">Somewhere else</option>
                </select>
                <span className="mt-1.5 block text-xs text-faint">
                  The legal age differs by country — here it&apos;s {required}+.
                </span>
              </label>

              <label className="block">
                <span className="label mb-1.5 block text-faint">Date of birth</span>
                <input
                  type="date"
                  value={value}
                  max={today}
                  onChange={(e) => {
                    setValue(e.target.value);
                    setError(null);
                  }}
                  className="tnum w-full border-b border-line-strong bg-transparent pb-2 text-[15px] outline-none focus:border-ink"
                />
              </label>

              {error && <p className="mt-2 text-sm text-accent">{error}</p>}

              <button
                type="submit"
                className="mt-6 w-full rounded-ctl bg-ink py-3 text-sm font-medium uppercase tracking-[0.12em] text-paper transition-opacity hover:opacity-90"
              >
                Enter
              </button>
            </form>

            <p className="mt-4 text-xs leading-relaxed text-faint">
              Please drink responsibly. Your date of birth isn&apos;t sent anywhere or saved — we check it, then keep
              only a yes on this device.
            </p>
          </>
        )}
      </div>
    </div>
  );
}
