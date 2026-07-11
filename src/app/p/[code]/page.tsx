"use client";

// The shareable invite — /p/<code> — openable by ANYONE, signed in or not.
// Anon: shows the safe preview (party_preview rpc) and points to the landing;
// the code is remembered and auto-joined after sign-in. Authed: one tap to join.
import Link from "next/link";
import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { fetchPartyPreview, joinParty, rememberPartyCode, type PartyPreview } from "@/lib/parties";
import { useAuth } from "@/lib/profile";
import { MONTH_NAMES, parseKey } from "@/lib/date";

export default function Page() {
  const { code } = useParams<{ code: string }>();
  const router = useRouter();
  const { status, profile } = useAuth();
  const [preview, setPreview] = useState<PartyPreview | null | "missing">(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let active = true;
    fetchPartyPreview(code).then((p) => active && setPreview(p ?? "missing"));
    return () => {
      active = false;
    };
  }, [code]);

  // signed out: keep the code so signing up finishes the job
  useEffect(() => {
    if (status === "anon" && preview && preview !== "missing") rememberPartyCode(code);
  }, [status, preview, code]);

  async function join() {
    if (busy) return;
    setBusy(true);
    const r = await joinParty(code);
    if ("error" in r) {
      setError(r.error);
      setBusy(false);
    } else {
      router.push(`/party/${r.id}`);
    }
  }

  if (preview === null || status === "loading") {
    return <div className="glass mx-auto mt-16 h-40 max-w-sm animate-pulse rounded-tile" aria-hidden />;
  }
  if (preview === "missing") {
    return (
      <div className="mx-auto mt-16 max-w-sm text-center">
        <p className="font-display text-2xl">No party here.</p>
        <p className="mt-2 text-sm text-muted">The link may be stale, or the party was called off.</p>
        <Link href="/" className="mt-6 inline-block text-sm font-medium text-accent hover:opacity-80">
          Go to brewdiary →
        </Link>
      </div>
    );
  }

  const d = parseKey(preview.date);
  return (
    <div className="mx-auto mt-12 max-w-sm">
      <div className="glass-strong rounded-tile p-7 text-center">
        <p className="label mb-2 text-faint">You&apos;re invited</p>
        <h1 className="font-display text-3xl leading-tight tracking-tight">{preview.name}</h1>
        <p className="mt-3 text-[15px] text-muted">
          <span className="tnum">
            {MONTH_NAMES[d.getMonth()]} {d.getDate()}
          </span>
          {preview.venue && ` · ${preview.venue}`}
        </p>
        <p className="mt-1 text-xs text-faint">
          hosted by {preview.hostName}
          {preview.going > 0 && (
            <>
              {" · "}
              <span className="tnum">{preview.going}</span> going
            </>
          )}
        </p>

        {profile ? (
          <>
            <button
              onClick={join}
              disabled={busy}
              className="mt-6 w-full rounded-ctl bg-ink py-3 text-base font-medium text-paper transition-all hover:bg-ink/90 active:scale-[0.99]"
            >
              {busy ? "Sending…" : "Ask to join"}
            </button>
            <p className="mt-3 text-xs text-faint">The host approves who comes in — you&apos;ll be let in once they do.</p>
          </>
        ) : (
          <>
            <Link
              href="/"
              className="mt-6 block w-full rounded-ctl bg-ink py-3 text-base font-medium text-paper transition-all hover:bg-ink/90 active:scale-[0.99]"
            >
              Start your diary to RSVP
            </Link>
            <p className="mt-3 text-xs text-faint">
              Sign in and you&apos;ll land right in this party — the invite is remembered.
            </p>
          </>
        )}
        {error && <p className="mt-3 text-sm text-muted">{error}</p>}
      </div>
    </div>
  );
}
