"use client";

import { useEffect, useState } from "react";
import { confirmAge, isAgeConfirmed, LEGAL_AGE } from "@/lib/age";

// Shown over everything on first visit until a valid date of birth is entered.
// Visibility is driven by the `needs-age` class on <html> (set flash-free by the
// inline script in layout.tsx) + CSS in globals.css, so it never flickers.
export function AgeGate() {
  const [state, setState] = useState<"gate" | "blocked" | "done">("gate");
  const [value, setValue] = useState("");
  const [error, setError] = useState<string | null>(null);

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
    if (confirmAge(dob)) {
      document.documentElement.classList.remove("needs-age");
      setState("done");
    } else {
      setState("blocked");
    }
  }

  if (state === "done") return null;

  return (
    <div className="age-gate fixed inset-0 z-[60] flex items-center justify-center p-5">
      <div className="glass-strong w-full max-w-sm rounded-tile p-7 sm:p-8">
        <p className="font-display text-lg italic text-muted">brewdiary</p>

        {state === "blocked" ? (
          <>
            <h1 className="mt-4 font-display text-3xl leading-tight text-ink">Not just yet.</h1>
            <p className="mt-3 text-[15px] leading-relaxed text-muted">
              You need to be of legal drinking age ({LEGAL_AGE}+) to use brewdiary. Come back when you are.
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

            <form onSubmit={submit} className="mt-6">
              <label className="block">
                <span className="label mb-1.5 block text-faint">Date of birth</span>
                <input
                  type="date"
                  value={value}
                  max={new Date().toISOString().slice(0, 10)}
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
              Please drink responsibly. We store this on your device only.
            </p>
          </>
        )}
      </div>
    </div>
  );
}
