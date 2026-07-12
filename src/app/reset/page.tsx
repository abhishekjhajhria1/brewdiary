"use client";

// Password-reset landing. The email link brings the user here with a recovery
// token; supabase-js (createBrowserClient, detectSessionInUrl) turns it into a
// short-lived session. Setting the NEW password happens over a server route
// (/api/auth/password) because browser-side `auth.updateUser()` can hang forever
// on supabase-js's internal lock — the server path always resolves. Public route
// (not in the middleware matcher) — the token arrives client-side, not as a cookie.
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase";

export default function ResetPage() {
  const router = useRouter();
  const [phase, setPhase] = useState<"checking" | "ready" | "invalid">("checking");
  const [linkError, setLinkError] = useState<string | null>(null);
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [confirmTouched, setConfirmTouched] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!supabase) {
      setPhase("invalid");
      return;
    }
    const sb = supabase;
    let settled = false;
    const ready = () => {
      settled = true;
      setPhase("ready");
    };
    const fail = (msg?: string) => {
      if (settled) return;
      settled = true;
      if (msg) setLinkError(msg);
      setPhase("invalid");
    };

    // Supabase reports link problems in the URL (?error_description=… or #error_description=…) —
    // surface the real reason instead of a generic timeout.
    const hashParams = new URLSearchParams(window.location.hash.slice(1));
    const queryParams = new URLSearchParams(window.location.search);
    const urlError = hashParams.get("error_description") || queryParams.get("error_description");
    if (urlError) {
      fail(urlError.replace(/\+/g, " "));
      return;
    }

    // token_hash links (cross-device safe — works even when the email is opened in a
    // different browser than the one that requested the reset) → verify explicitly.
    const tokenHash = queryParams.get("token_hash");
    if (tokenHash) {
      sb.auth
        .verifyOtp({ type: "recovery", token_hash: tokenHash })
        .then(({ error }) => (error ? fail(error.message) : ready()))
        .catch(() => fail("Couldn't reach the server — check your connection and reopen the link."));
      return;
    }

    // PKCE links (?code=…) are exchanged automatically on load; watch for the session.
    const { data: sub } = sb.auth.onAuthStateChange((event, session) => {
      if (event === "PASSWORD_RECOVERY" || session) ready();
    });
    sb.auth.getSession().then(({ data }) => {
      if (data.session) ready();
    });
    // no recovery session after a grace period → stale/used link (or opened in a
    // different browser than the one that asked for it)
    const t = setTimeout(() => fail(), 8000);
    return () => {
      sub.subscription.unsubscribe();
      clearTimeout(t);
    };
  }, []);

  const mismatch = confirmTouched && confirm.length > 0 && confirm !== password;
  const canSubmit = password.length >= 6 && confirm === password && !busy;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!canSubmit) {
      setConfirmTouched(true);
      if (confirm !== password) setError("The two passwords don't match.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      // Hard 15s cap — this form must never spin forever again.
      const ctrl = new AbortController();
      const kill = setTimeout(() => ctrl.abort(), 15_000);
      const res = await fetch("/api/auth/password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ password }),
        signal: ctrl.signal,
      });
      clearTimeout(kill);
      if (!res.ok) {
        const body = await res.json().catch(() => null);
        setError(body?.error || "Couldn't save the new password — try again.");
        setBusy(false);
        return;
      }
    } catch {
      setError("That took too long — check your connection and try again.");
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
              {linkError ??
                "This reset link is invalid, already used, or was opened in a different browser than the one that requested it. Head back and request a fresh one from “Forgot password?”."}
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
                  autoComplete="new-password"
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
                  autoComplete="new-password"
                  value={confirm}
                  onChange={(e) => setConfirm(e.target.value)}
                  onBlur={() => setConfirmTouched(true)}
                  placeholder="Type it again"
                  className="w-full border-b border-line-strong bg-transparent pb-2 text-[15px] outline-none placeholder:text-faint focus:border-ink"
                />
                {mismatch && <span className="mt-1.5 block text-sm text-accent">The two passwords don&apos;t match.</span>}
              </label>
              {error && <p className="text-sm text-accent">{error}</p>}
              <button
                type="submit"
                disabled={!canSubmit}
                className="w-full rounded-ctl bg-ink py-3 text-sm font-medium uppercase tracking-[0.12em] text-paper transition-opacity hover:opacity-90 disabled:opacity-40"
              >
                {busy ? "Saving…" : "Save new password"}
              </button>
            </form>
          </>
        )}
      </div>
    </div>
  );
}
