"use client";

// ProfileCard — share your diary as a poster the way ScoreCard/ShareCard do: the same
// 1080×1350 export scaffold and warm export palette (see ./canvas). It's the shareable
// face of a public profile — a monogram, your name + handle, the all-time totals, and a
// baked-in 12-week streak mosaic.
//
// House rules kept: counts only. Name, handle, totals, and the mosaic — never a note, a
// venue, a ₹ figure, or where anyone was. Exactly what /u/<handle> already shows a stranger,
// just as a picture you can post.
import { useCallback, useEffect, useRef, useState } from "react";
import { intensityLevel } from "@/lib/derive";
import { addDays, parseKey, toKey, todayKey } from "@/lib/date";
import {
  ACCENT,
  H,
  INK,
  PAPER,
  W,
  canShareFiles,
  downloadCanvas,
  fontsReady,
  mark,
  shareCanvas,
} from "./canvas";

export interface ShareProfile {
  name: string;
  handle: string;
  total: number;
  kinds: number;
  /** Distinct days logged in the 12-week window (derived from `counts`). */
  activeDays: number;
  /** day-key → logs that day, last 12 weeks — the mosaic. */
  counts: Map<string, number>;
  /** The Palate Score + the level/title it earns (lib/score). */
  score: number;
  title: string;
  level: number;
  /** Lifetime best streak, if known (migration 046); otherwise the card shows active days. */
  longestStreak?: number;
}

function initials(name: string): string {
  return (
    name
      .replace(/[^\p{L}\p{N} ]/gu, "")
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((w) => w[0]!.toUpperCase())
      .join("") || "?"
  );
}

export function ProfileCard({ profile, onClose }: { profile: ShareProfile; onClose: () => void }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [rendering, setRendering] = useState(true);

  const draw = useCallback(async () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    setRendering(true);
    await fontsReady();
    drawProfile(ctx, profile);
    setRendering(false);
  }, [profile]);

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

  const file = "brewdiary-profile.png";
  const download = () => downloadCanvas(canvasRef.current, file);
  const share = () =>
    shareCanvas(canvasRef.current, file, `${profile.name} on brewdiary — ${profile.title}, palate score ${profile.score}`);

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

// ─── canvas template ───────────────────────────────────────────────
const SUB = "#6e665c";
const CELL_EMPTY = "#e7ded0";
const cellFill = (lvl: number) => (lvl === 0 ? CELL_EMPTY : `rgba(184,116,42,${(0.22 + lvl * 0.19).toFixed(3)})`);

function drawProfile(ctx: CanvasRenderingContext2D, p: ShareProfile) {
  ctx.clearRect(0, 0, W, H);
  ctx.fillStyle = PAPER;
  ctx.fillRect(0, 0, W, H);

  const M = 88; // margin

  // wordmark
  ctx.textAlign = "left";
  ctx.fillStyle = SUB;
  ctx.font = "italic 38px 'Newsreader', serif";
  ctx.fillText("brewdiary", M, 104);

  // identity — monogram + name + handle
  const cx = M + 42;
  const cy = 208;
  ctx.beginPath();
  ctx.arc(cx, cy, 42, 0, Math.PI * 2);
  ctx.fillStyle = "rgba(184,116,42,0.14)";
  ctx.fill();
  ctx.fillStyle = INK;
  ctx.font = "600 38px 'Newsreader', serif";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(initials(p.name), cx, cy + 3);
  ctx.textBaseline = "alphabetic";

  ctx.textAlign = "left";
  ctx.fillStyle = INK;
  ctx.font = "700 54px 'Newsreader', serif";
  ctx.fillText(clip(ctx, p.name, W - M * 2 - 100), M + 104, 200);
  ctx.fillStyle = SUB;
  ctx.font = "400 30px 'Hanken Grotesk', sans-serif";
  ctx.fillText(`@${p.handle}`, M + 104, 244);

  // the hero — the palate score, big, with its level + title beside it
  ctx.fillStyle = ACCENT;
  ctx.font = "600 28px 'Hanken Grotesk', sans-serif";
  ctx.fillText("PALATE SCORE", M, 372);

  ctx.fillStyle = INK;
  ctx.font = "700 220px 'Newsreader', serif";
  const scoreStr = String(p.score);
  ctx.fillText(scoreStr, M, 560);
  const scoreW = ctx.measureText(scoreStr).width;

  const bx = M + scoreW + 44;
  ctx.fillStyle = SUB;
  ctx.font = "600 26px 'Hanken Grotesk', sans-serif";
  ctx.fillText(`LEVEL ${p.level}`, bx, 470);
  ctx.fillStyle = INK;
  ctx.font = "italic 52px 'Newsreader', serif";
  ctx.fillText(clip(ctx, p.title, W - bx - M), bx, 528);

  // stat strip — a hairline over three lifetime figures
  const third: [number, string] =
    p.longestStreak !== undefined ? [p.longestStreak, "best streak"] : [p.activeDays, "active days"];
  const stats: [number, string][] = [
    [p.total, "logged"],
    [p.kinds, "kinds"],
    third,
  ];
  const stripY = 660;
  ctx.strokeStyle = "#e2d9ca";
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(M, stripY);
  ctx.lineTo(W - M, stripY);
  ctx.stroke();
  const colW = (W - M * 2) / 3;
  stats.forEach(([value, label], i) => {
    const x = M + colW * i;
    ctx.fillStyle = INK;
    ctx.font = "700 76px 'Newsreader', serif";
    ctx.fillText(String(value), x, stripY + 96);
    ctx.fillStyle = SUB;
    ctx.font = "600 24px 'Hanken Grotesk', sans-serif";
    ctx.fillText(label.toUpperCase(), x, stripY + 138);
  });

  // mosaic — the last 12 weeks, Monday-first, matching RecentMosaic's grid
  ctx.fillStyle = SUB;
  ctx.font = "600 26px 'Hanken Grotesk', sans-serif";
  ctx.fillText("THE LAST 12 WEEKS", M, 900);
  drawMosaic(ctx, p.counts, M, 940, W - M * 2);

  // mark
  mark(ctx, M + 8, H - 84, INK);
  ctx.fillStyle = SUB;
  ctx.font = "italic 34px 'Newsreader', serif";
  ctx.fillText("bwdy.site", M + 36, H - 74);
}

function drawMosaic(ctx: CanvasRenderingContext2D, counts: Map<string, number>, x: number, y: number, width: number) {
  const WEEKS = 12;
  const gap = 10;
  const cell = (width - gap * (WEEKS - 1)) / WEEKS;
  const today = parseKey(todayKey());
  const dow = (today.getDay() + 6) % 7; // Monday-first
  const end = addDays(today, 6 - dow);
  const start = addDays(end, -(WEEKS * 7 - 1));

  let cursor = start;
  for (let w = 0; w < WEEKS; w++) {
    for (let d = 0; d < 7; d++) {
      const key = toKey(cursor);
      const future = cursor.getTime() > today.getTime();
      const lvl = intensityLevel(counts.get(key) ?? 0);
      const px = x + w * (cell + gap);
      const py = y + d * (cell + gap);
      ctx.fillStyle = future ? PAPER : cellFill(lvl);
      roundRect(ctx, px, py, cell, cell, 5);
      ctx.fill();
      cursor = addDays(cursor, 1);
    }
  }
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

// Truncate a single line to fit maxW, with an ellipsis.
function clip(ctx: CanvasRenderingContext2D, text: string, maxW: number): string {
  if (ctx.measureText(text).width <= maxW) return text;
  let s = text;
  while (s.length > 1 && ctx.measureText(`${s}…`).width > maxW) s = s.slice(0, -1);
  return `${s}…`;
}
