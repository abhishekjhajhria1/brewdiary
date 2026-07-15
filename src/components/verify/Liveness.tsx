"use client";

// The live-camera check. A short, randomised challenge — "blink twice", "smile" —
// verified on-device with MediaPipe FaceLandmarker blendshapes.
//
// ── WHAT THIS IS (and the honesty that governs the copy) ─────────────────────
// This is an ANTI-BOT / anti-throwaway signal, not identity verification. It raises
// the cost of mass fake accounts; a determined person could still defeat it with a
// video of a real face. So nothing here says "verified" — it earns "trusted member".
// Real identity proof is the paid vendor void (lib/verify.ts), for later.
//
// PRIVACY: every frame stays in the browser. MediaPipe runs the model locally (WASM);
// we never upload an image, and we keep nothing but a boolean "passed". The only
// network is fetching the static model/WASM the first time (like loading a font).
//
// PERFORMANCE: @mediapipe/tasks-vision is imported DYNAMICALLY, so its ~2–3MB of wasm
// + model land only when someone opens this screen — never in the app's main bundle.
//
// ⚠ NEEDS ON-DEVICE TESTING: thresholds (BLINK_HI/LO, SMILE) are tuned by eye and may
//   want adjusting on real cameras/lighting. The flow degrades gracefully — no camera,
//   no model, or a timeout all end in a clear message, never a hang.
import { useCallback, useEffect, useRef, useState } from "react";
import { recordPresence } from "@/lib/verify";

// Blendshape score thresholds (0..1). A blink is eyes-closed crossing HI then LO.
const BLINK_HI = 0.5;
const BLINK_LO = 0.2;
const SMILE = 0.5;
const CHALLENGE_MS = 20_000; // per-challenge time budget before we call it a miss

// The MediaPipe model + wasm. Loaded from the CDN on this screen only. (TODO: self-host
// under /public for full offline + zero third-party fetch — a hardening follow-up.)
const WASM_URL = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.35/wasm";
const MODEL_URL =
  "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";

type Step = "intro" | "loading" | "blink" | "smile" | "passed" | "failed" | "nocam";

export function Liveness({ onClose }: { onClose: (passed: boolean) => void }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const landmarkerRef = useRef<any>(null);
  const rafRef = useRef<number | null>(null);
  const [step, setStep] = useState<Step>("intro");
  const [error, setError] = useState<string | null>(null);

  const cleanup = useCallback(() => {
    if (rafRef.current) cancelAnimationFrame(rafRef.current);
    rafRef.current = null;
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    try {
      landmarkerRef.current?.close?.();
    } catch {
      /* ignore */
    }
    landmarkerRef.current = null;
  }, []);

  useEffect(() => cleanup, [cleanup]);

  // Advance a tiny state machine: load model+camera → blink twice → smile → pass.
  const start = useCallback(async () => {
    setError(null);
    setStep("loading");
    try {
      // 1) camera
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "user" }, audio: false });
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
      }

      // 2) model (dynamic import keeps this out of the main bundle)
      const vision = await import("@mediapipe/tasks-vision");
      const fileset = await vision.FilesetResolver.forVisionTasks(WASM_URL);
      landmarkerRef.current = await vision.FaceLandmarker.createFromOptions(fileset, {
        baseOptions: { modelAssetPath: MODEL_URL, delegate: "GPU" },
        outputFaceBlendshapes: true,
        runningMode: "VIDEO",
        numFaces: 1,
      });

      runChallenge("blink");
    } catch (e) {
      const msg = (e as Error)?.name === "NotAllowedError" ? "nocam" : "err";
      if (msg === "nocam") {
        setStep("nocam");
      } else {
        setError("Couldn't start the camera check. Your connection or camera may be blocked.");
        setStep("failed");
      }
      cleanup();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cleanup]);

  // Run one challenge to completion, then hand off to the next.
  const runChallenge = useCallback((which: "blink" | "smile") => {
    setStep(which);
    const deadline = performance.now() + CHALLENGE_MS;
    let blinkCount = 0;
    let eyesClosed = false;

    const tick = () => {
      const video = videoRef.current;
      const lm = landmarkerRef.current;
      if (!video || !lm) return;

      let scores: Record<string, number> = {};
      try {
        const res = lm.detectForVideo(video, performance.now());
        const cats = res?.faceBlendshapes?.[0]?.categories as { categoryName: string; score: number }[] | undefined;
        if (cats) scores = Object.fromEntries(cats.map((c) => [c.categoryName, c.score]));
      } catch {
        /* a dropped frame — keep going */
      }

      if (which === "blink") {
        const closed = (scores.eyeBlinkLeft ?? 0) > BLINK_HI && (scores.eyeBlinkRight ?? 0) > BLINK_HI;
        const open = (scores.eyeBlinkLeft ?? 0) < BLINK_LO && (scores.eyeBlinkRight ?? 0) < BLINK_LO;
        if (closed && !eyesClosed) eyesClosed = true;
        if (open && eyesClosed) {
          eyesClosed = false;
          blinkCount += 1;
        }
        if (blinkCount >= 2) return runChallenge("smile");
      } else {
        const smiling = (scores.mouthSmileLeft ?? 0) > SMILE && (scores.mouthSmileRight ?? 0) > SMILE;
        if (smiling) return pass();
      }

      if (performance.now() > deadline) {
        setError("Didn't quite catch that — the light may be low, or the camera couldn't see your face. Try again?");
        setStep("failed");
        cleanup();
        return;
      }
      rafRef.current = requestAnimationFrame(tick);
    };
    rafRef.current = requestAnimationFrame(tick);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cleanup]);

  const pass = useCallback(async () => {
    cleanup();
    setStep("passed");
    await recordPresence();
  }, [cleanup]);

  return (
    <div className="fixed inset-0 z-60 flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true">
      <div className="glass-strong w-full max-w-sm rounded-tile p-6">
        <div className="mb-4 flex items-center justify-between">
          <p className="label text-faint">A quick camera check</p>
          <button onClick={() => { cleanup(); onClose(step === "passed"); }} className="text-faint transition-colors hover:text-ink" aria-label="Close">
            ✕
          </button>
        </div>

        {/* the live preview (mirrored, so it feels like a mirror) */}
        <div className="relative mb-4 aspect-[4/3] overflow-hidden rounded-ctl bg-black/30">
          <video ref={videoRef} playsInline muted className="h-full w-full -scale-x-100 object-cover" />
          {(step === "blink" || step === "smile") && (
            <p className="absolute inset-x-0 bottom-0 bg-black/50 py-2 text-center text-sm font-medium text-white">
              {step === "blink" ? "Blink twice" : "Now give a little smile"}
            </p>
          )}
        </div>

        {step === "intro" && (
          <>
            <p className="text-[15px] leading-relaxed text-muted">
              This earns you a <span className="text-ink">trusted member</span> mark — it just checks there&apos;s a
              real person here. It runs entirely on your phone; <span className="text-ink">no photo is taken or
              uploaded</span>, and we keep only that you passed.
            </p>
            <button onClick={start} className="mt-4 w-full rounded-ctl bg-ink py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90">
              Start
            </button>
          </>
        )}
        {step === "loading" && <p className="text-sm text-faint">Warming up the camera…</p>}
        {step === "passed" && (
          <>
            <p className="text-[15px] text-ink">Done — you&apos;re a trusted member now.</p>
            <button onClick={() => onClose(true)} className="mt-4 w-full rounded-ctl bg-ink py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90">
              Nice
            </button>
          </>
        )}
        {step === "nocam" && (
          <>
            <p className="text-[15px] leading-relaxed text-muted">
              We couldn&apos;t reach your camera — it may be blocked in your browser settings. You can still use
              everything else; this just stays optional.
            </p>
            <button onClick={() => onClose(false)} className="mt-4 w-full rounded-ctl bg-ink py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90">
              Okay
            </button>
          </>
        )}
        {step === "failed" && (
          <>
            <p className="text-[15px] leading-relaxed text-muted">{error ?? "That didn't work — try again?"}</p>
            <div className="mt-4 flex gap-3">
              <button onClick={start} className="flex-1 rounded-ctl bg-ink py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90">
                Try again
              </button>
              <button onClick={() => onClose(false)} className="text-sm text-faint transition-colors hover:text-ink">
                Later
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
