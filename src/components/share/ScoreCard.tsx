"use client";

// ScoreCard — share a SCORE the way ShareCard shares an entry. Same 1080×1350
// export scaffold, same warm export palette (see ./canvas).
//
// What it will and won't say:
//   • sparks + vibe, and where they came from ("The Tap Room", "with friends").
//   • NEVER spend, never a bill, never a ₹ figure. Nobody flexes money here —
//     that was the whole point of the three-currency model.
//   • rank only if you're actually on a board, and only as "2nd of 6" — never
//     a name-and-shame of whoever is below you.
import { useCallback, useEffect, useRef, useState } from "react";
import clsx from "clsx";
import {
  ACCENT,
  H,
  INK,
  PAPER,
  W,
  canShareFiles,
  coverImage,
  downloadCanvas,
  fontsReady,
  loadImage,
  mark,
  shareCanvas,
  wrap,
} from "./canvas";

type Template = "minimal" | "poster";

export interface Score {
  name: string;
  sparks: number;
  vibe: number;
  /** Where it happened — a room or venue name, or "with friends". */
  context?: string;
  /** 1-based position on whatever board this came from, if any. */
  rank?: number;
  of?: number;
}

export function ScoreCard({ score, onClose }: { score: Score; onClose: () => void }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [template, setTemplate] = useState<Template>("minimal");
  const [bg, setBg] = useState<string | null>(null);
  const [rendering, setRendering] = useState(true);

  const draw = useCallback(async () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    setRendering(true);
    await fontsReady();
    const img = bg ? await loadImage(bg) : null;

    if (template === "minimal") drawMinimal(ctx, img, score);
    else drawPoster(ctx, img, score);
    setRendering(false);
  }, [bg, template, score]);

  useEffect(() => {
    draw();
  }, [draw]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [onClose]);

  function pickPhoto(f: File | undefined) {
    if (!f) return;
    const r = new FileReader();
    r.onload = () => setBg(String(r.result));
    r.readAsDataURL(f);
  }

  const file = "brewdiary-score.png";
  const download = () => downloadCanvas(canvasRef.current, file);
  const share = () =>
    shareCanvas(canvasRef.current, file, `${score.sparks} sparks${score.vibe > 0 ? `, ${score.vibe} vibe` : ""}`);

  return (
    <div className="fixed inset-0 z-60 flex flex-col items-center justify-center gap-4 bg-ink/40 p-5">
      <button aria-label="Close" onClick={onClose} className="absolute inset-0" />

      <div className="relative flex w-full max-w-sm flex-col items-center gap-4">
        <canvas
          ref={canvasRef}
          width={W}
          height={H}
          className="w-full rounded-xl shadow-[0_8px_40px_rgba(0,0,0,0.35)]"
          style={{ aspectRatio: "1080 / 1350" }}
        />

        <div className="flex w-full items-center justify-center gap-1.5">
          <Toggle active={template === "minimal"} onClick={() => setTemplate("minimal")}>
            Minimal
          </Toggle>
          <Toggle active={template === "poster"} onClick={() => setTemplate("poster")}>
            Poster
          </Toggle>
          <label className="cursor-pointer rounded-ctl border border-paper/40 px-3 py-1.5 text-xs uppercase tracking-[0.12em] text-paper transition-colors hover:bg-paper/10">
            Photo
            <input type="file" accept="image/*" className="hidden" onChange={(e) => pickPhoto(e.target.files?.[0])} />
          </label>
        </div>

        <div className="flex w-full gap-2">
          <button
            onClick={share}
            disabled={rendering}
            className="flex-1 rounded-ctl bg-accent py-3 text-sm font-medium text-accent-contrast transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            {canShareFiles() ? "Share" : "Download"}
          </button>
          <button
            onClick={download}
            disabled={rendering}
            className="rounded-ctl border border-paper/40 px-4 py-3 text-sm text-paper transition-colors hover:bg-paper/10 disabled:opacity-50"
          >
            Save
          </button>
        </div>
        <button onClick={onClose} className="text-sm text-paper/70 transition-colors hover:text-paper">
          Close
        </button>
      </div>
    </div>
  );
}

function Toggle({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={clsx(
        "rounded-ctl px-3 py-1.5 text-xs uppercase tracking-[0.12em] transition-colors",
        active ? "bg-paper text-ink" : "border border-paper/40 text-paper hover:bg-paper/10",
      )}
    >
      {children}
    </button>
  );
}

// ─── canvas templates ───────────────────────────────────────────────

const ordinal = (n: number) => {
  const s = ["th", "st", "nd", "rd"];
  const v = n % 100;
  return `${n}${s[(v - 20) % 10] ?? s[v] ?? s[0]}`;
};

function rankLine(score: Score): string {
  if (!score.rank || !score.of || score.of < 2) return "";
  return `${ordinal(score.rank)} of ${score.of}`;
}

function drawMinimal(ctx: CanvasRenderingContext2D, img: HTMLImageElement | null, score: Score) {
  ctx.clearRect(0, 0, W, H);
  const onPhoto = Boolean(img);

  if (img) {
    coverImage(ctx, img);
    const g = ctx.createLinearGradient(0, H * 0.35, 0, H);
    g.addColorStop(0, "rgba(0,0,0,0)");
    g.addColorStop(1, "rgba(0,0,0,0.66)");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
  } else {
    ctx.fillStyle = PAPER;
    ctx.fillRect(0, 0, W, H);
  }

  const fg = onPhoto ? PAPER : INK;
  const sub = onPhoto ? "rgba(250,246,238,0.82)" : "#6e665c";

  ctx.textAlign = "left";
  ctx.fillStyle = sub;
  ctx.font = "italic 36px 'Newsreader', serif";
  ctx.fillText("brewdiary", 72, 96);

  // the rank, small and quiet, above the number
  const rl = rankLine(score);
  if (rl) {
    ctx.fillStyle = ACCENT;
    ctx.font = "600 26px 'Hanken Grotesk', sans-serif";
    ctx.fillText(rl.toUpperCase(), 72, H - 470);
  }

  // the number does the talking
  ctx.fillStyle = fg;
  ctx.font = "700 260px 'Newsreader', serif";
  ctx.fillText(String(score.sparks), 72, H - 300);

  ctx.fillStyle = sub;
  ctx.font = "600 34px 'Hanken Grotesk', sans-serif";
  ctx.fillText(score.sparks === 1 ? "SPARK" : "SPARKS", 72, H - 240);

  if (score.vibe > 0) {
    ctx.fillStyle = fg;
    ctx.font = "italic 46px 'Newsreader', serif";
    ctx.fillText(`and ${score.vibe} vibe from the room`, 72, H - 150);
  }

  ctx.fillStyle = sub;
  ctx.font = "italic 40px 'Newsreader', serif";
  const meta = [score.name, score.context].filter(Boolean).join("  ·  ");
  ctx.fillText(wrap(ctx, meta, W - 200, 1)[0] ?? "", 72, H - 80);

  mark(ctx, W - 96, H - 96, onPhoto ? PAPER : INK);
}

function drawPoster(ctx: CanvasRenderingContext2D, img: HTMLImageElement | null, score: Score) {
  ctx.clearRect(0, 0, W, H);
  ctx.fillStyle = INK;
  ctx.fillRect(0, 0, W, H);

  if (img) {
    const top = H * 0.42;
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, top, W, H - top);
    ctx.clip();
    const scale = Math.max(W / img.width, (H - top) / img.height);
    const w = img.width * scale;
    const h = img.height * scale;
    ctx.globalAlpha = 0.9;
    ctx.drawImage(img, (W - w) / 2, top, w, h);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = "multiply";
    ctx.fillStyle = ACCENT;
    ctx.fillRect(0, top, W, H - top);
    ctx.globalCompositeOperation = "source-over";
    ctx.restore();
  }

  ctx.textAlign = "left";
  ctx.fillStyle = ACCENT;
  ctx.font = "600 30px 'Hanken Grotesk', sans-serif";
  ctx.fillText("BREWDIARY", 72, 120);

  ctx.fillStyle = PAPER;
  ctx.font = "700 200px 'Newsreader', serif";
  ctx.fillText(String(score.sparks), 72, 300);

  ctx.fillStyle = "rgba(250,246,238,0.72)";
  ctx.font = "600 30px 'Hanken Grotesk', sans-serif";
  const head = [score.sparks === 1 ? "SPARK" : "SPARKS", score.vibe > 0 ? `${score.vibe} VIBE` : ""]
    .filter(Boolean)
    .join("   ·   ");
  ctx.fillText(head, 72, 360);

  // a spark-count motif: filled squares up to 7, dimmed beyond
  const my = 420;
  for (let i = 0; i < 7; i++) {
    const lit = i < Math.min(score.sparks, 7);
    ctx.fillStyle = lit ? `rgba(250,246,238,${0.35 + i * 0.09})` : "rgba(250,246,238,0.12)";
    ctx.fillRect(72 + i * 46, my, 34, 34);
  }

  // bottom: who, where, rank
  ctx.fillStyle = PAPER;
  ctx.font = "italic 44px 'Newsreader', serif";
  ctx.fillText(wrap(ctx, score.name, W - 144, 1)[0] ?? "", 72, H - 120);

  ctx.fillStyle = "rgba(250,246,238,0.7)";
  ctx.font = "600 28px 'Hanken Grotesk', sans-serif";
  const meta = [score.context?.toUpperCase(), rankLine(score).toUpperCase()].filter(Boolean).join("   ·   ");
  ctx.fillText(wrap(ctx, meta, W - 144, 1)[0] ?? "", 72, H - 72);
}
