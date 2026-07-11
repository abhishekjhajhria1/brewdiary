"use client";

// Password-reset landing. The email link brings the user here with a recovery
// token in the URL; supabase-js (createBrowserClient, detectSessionInUrl) turns
// it into a short-lived session and fires PASSWORD_RECOVERY. We then let them set
// a new password (updateUser) and drop them straight into the diary. Public route
// (not in the middleware matcher) — the token arrives client-side, not as a cookie.
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase";
import { updatePassword } from "@/lib/profile";

export default function ResetPage() {
  const router = useRouter();
  const [phase, setPhase] = useState<"checking" | "ready" | "invalid">("checking");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!supabase) {
      setPhase("invalid");
      return;
    }
    let settled = false;
    const ready = () => {
      settled = true;
      setPhase("ready");
    };
    // supabase-js processes the recovery token in the URL on load, then fires this
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === "PASSWORD_RECOVERY" || session) ready();
    });
    // …or the session may already be established by the time we mount
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) ready();
    });
    // no recovery session after a moment → the link is stale or was already used
    const t = setTimeout(() => {
      if (!settled) setPhase("invalid");
    }, 3000);
    return () => {
      sub.subscription.unsubscribe();
      clearTimeout(t);
    };
  }, []);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    if (password.length < 6) {
      setError("At least 6 characters.");
      return;
    }
    if (password !== confirm) {
      setError("Those don't match.");
      return;
    }
    setBusy(true);
    setError(null);
    const res = await updatePassword(password);
    if (!res.ok) {
      setError(res.error);
      setBusy(false);
      return;
    }
    // new password set + a live session → straight into the diary
    router.push("/");
    router.refresh();
  }

  return (
    <div className="mx-auto mt-16 max-w-md">
      <div className="glass-strong rounded-tile bg-canvas/95 p-7 sm:p-8">
        <p className="label mb-3 text-muted">brewdiary</p>

        {phase === "checking" ? (
          <>
            <h1 className="display text-3xl leading-tight">One moment…</h1>
            <p className="mt-3 text-[15px] text-muted">Checking your reset link.</p>
          </>
        ) : phase === "invalid" ? (
          <>
            <h1 className="display text-3xl leading-tight">Link expired.</h1>
            <p className="mt-3 text-[15px] leading-relaxed text-muted">
              This reset link is invalid or has already been used. Head back and request a fresh one from
              &ldquo;Forgot password?&rdquo;.
            </p>
            <Link
              href="/"
              className="mt-6 inline-block w-full rounded-ctl bg-ink py-3 text-center text-sm font-medium uppercase tracking-[0.12em] text-paper transition-opacity hover:opacity-90"
            >
              Back to sign in
            </Link>
          </>
        ) : (
          <>
            <h1 className="display text-3xl leading-tight">Set a new password.</h1>
            <p className="mt-3 text-[15px] text-muted">Pick something you&apos;ll remember.</p>
            <form onSubmit={submit} className="mt-6 space-y-4">
              <label className="block">
                <span className="label mb-1.5 block text-muted">New password</span>
                <input
                  type="password"
                  autoFocus
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="At least 6 characters"
                  className="w-full border-b border-line-strong bg-transparent pb-2 text-[15px] outline-none placeholder:text-faint focus:border-ink"
                />
              </label>
              <label className="block">
                <span className="label mb-1.5 block text-muted">Confirm</span>
                <input
                  type="password"
                  value={confirm}
                  onChange={(e) => setConfirm(e.target.value)}
                  placeholder="Type it again"
                  className="w-full border-b border-line-strong bg-transparent pb-2 text-[15px] outline-none placeholder:text-faint focus:border-ink"
                />
              </label>
              {error && <p className="text-sm text-accent">{error}</p>}
              <button
                type="submit"
                disabled={busy || password.length < 6}
                className="w-full rounded-ctl bg-ink py-3 text-sm font-medium uppercase tracking-[0.12em] text-paper transition-opacity hover:opacity-90 disabled:opacity-40"
              >
                {busy ? "…" : "Save new password"}
              </button>
            </form>
          </>
        )}
      </div>
    </div>
  );
}
