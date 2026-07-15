"use client";

// The trust card in You → settings. Shows the person their own trust level and how to
// raise it — a coarse anti-bot standing (are you a real, settled human), NOT a rating
// of you as a person and NOT a public ranking. The camera check and, later, friend
// vouches raise it; photo-ID verification is the paid void, shown as "coming soon"
// rather than a dead button.
import { useState } from "react";
import dynamic from "next/dynamic";
import { useMyTrust, TRUST_LABEL, identityVerificationAvailable } from "@/lib/verify";
import { useMyVouchCount } from "@/lib/vouch";
import { useProfile } from "@/lib/profile";

// MediaPipe lives inside Liveness — load it only when opened, and never on the server.
const Liveness = dynamic(() => import("./Liveness").then((m) => m.Liveness), { ssr: false });

export function TrustCard() {
  const profile = useProfile();
  const { level } = useMyTrust();
  const vouches = useMyVouchCount();
  const [checking, setChecking] = useState(false);
  const done = Boolean(profile?.presenceChecked);

  if (!profile) return null;

  return (
    <div className="mt-4 border-t border-line py-3">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm text-ink">Your standing</p>
        <span className="glass rounded-ctl px-2.5 py-1 text-xs font-medium text-muted">{TRUST_LABEL[level]}</span>
      </div>
      <p className="mb-3 mt-1 text-xs leading-relaxed text-faint">
        A quiet signal that you&apos;re a real, settled person — it grows as you use brewdiary and connect with
        friends. It helps others feel comfortable meeting up. It&apos;s never a score of you as a person, and
        nobody sees a ranking.
      </p>

      {done ? (
        <p className="text-sm text-accent">✓ You passed the camera check</p>
      ) : (
        <button
          onClick={() => setChecking(true)}
          className="rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90"
        >
          Do a quick camera check
        </button>
      )}
      {!done && (
        <p className="mt-1.5 text-xs text-faint">
          On-device only — no photo is taken or uploaded. Earns a &ldquo;trusted member&rdquo; mark.
        </p>
      )}

      {vouches > 0 && (
        <p className="mt-3 text-xs text-faint">
          <span className="text-muted">{vouches}</span> {vouches === 1 ? "friend vouches" : "friends vouch"} for you.
        </p>
      )}

      {/* the paid-vendor void — a real row, honestly "later", never a dead button */}
      <p className="mt-3 flex items-center justify-between gap-3 text-xs text-faint">
        <span>Photo-ID verification</span>
        <span>{identityVerificationAvailable ? "Available" : "Coming soon"}</span>
      </p>

      {checking && <Liveness onClose={() => setChecking(false)} />}
    </div>
  );
}
