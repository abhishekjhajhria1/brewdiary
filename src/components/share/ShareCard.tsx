"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import clsx from "clsx";
import { useEntries } from "@/lib/store";
import { countsByDate, currentStreak } from "@/lib/derive";
import { MONTH_NAMES, parseKey } from "@/lib/date";
import type { Entry } from "@/lib/types";

// Export-only artifact: its own warm palette, independent of the app theme.
const PAPER = "#faf6ee";
const INK = "#1b1714";
const ACCENT = "#b8742a";
const W = 1080;
const H = 1350;

type Template = "minimal" | "poster";

export function ShareCard({ entry, onClose }: { entry: Entry; onClose: () => void }) {
  const entries = useEntries();
  const streak = currentStreak(countsByDate(entries));
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [template, setTemplate] = useState<Template>("minimal");
  const [bg, setBg] = useState<string | null>(entry.photos?.[0]?.url ?? null);
  const [rendering, setRendering] = useState(true);

  const d = parseKey(entry.date);
  const dateLabel = `${MONTH_NAMES[d.getMonth()].slice(0, 3)} ${d.getDate()}`;

  const loadImage = (url: string) =>
    new Promise<HTMLImageElement | null>((resolve) => {
      const img = new Image();
      img.crossOrigin = "anonymous";
      img.onload = () => resolve(img);
      img.onerror = () => resolve(null);
      img.src = url;
    });

  const draw = useCallback(async () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    setRendering(true);
    try {
      await (document as Document & { fonts?: FontFaceSet }).fonts?.ready;
    } catch {
      /* fonts optional */
    }
    const img = bg ? await loadImage(bg) : null;

    if (template === "minimal") drawMinimal(ctx, { img, entry, dateLabel, streak });
    else drawPoster(ctx, { img, entry, dateLabel, streak });
    setRendering(false);
  }, [bg, template, entry, dateLabel, streak]);

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

  function pickPhoto(file: File | undefined) {
    if (!file) return;
    const r = new FileReader();
    r.onload = () => setBg(String(r.result));
    r.readAsDataURL(file);
  }

  function toBlob(): Promise<Blob | null> {
    return new Promise((resolve) => {
      const c = canvasRef.current;
      if (!c) return resolve(null);
      c.toBlob((b) => resolve(b), "image/png");
    });
  }

  async function download() {
    const blob = await toBlob();
    if (!blob) return;
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `brewdiary-${entry.date}.png`;
    a.click();
    URL.revokeObjectURL(url);
  }

  async function share() {
    const blob = await toBlob();
    if (!blob) return;
    const file = new File([blob], `brewdiary-${entry.date}.png`, { type: "image/png" });
    const nav = navigator as Navigator & { canShare?: (d: ShareData) => boolean };
    if (nav.canShare?.({ files: [file] })) {
      try {
        await nav.share({ files: [file], title: "brewdiary", text: `${entry.drink} — ${entry.mood ?? ""}` });
        return;
      } catch {
        /* user cancelled or unsupported — fall through to download */
      }
    }
    download();
  }

  const canShare = typeof navigator !== "undefined" && "canShare" in navigator;

  return (
    <div className="fixed inset-0 z-[60] flex flex-col items-center justify-center gap-4 bg-ink/40 p-5">
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
            {canShare ? "Share" : "Download"}
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
          Done
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

interface DrawArgs {
  img: HTMLImageElement | null;
  entry: Entry;
  dateLabel: string;
  streak: number;
}

function coverImage(ctx: CanvasRenderingContext2D, img: HTMLImageElement) {
  const scale = Math.max(W / img.width, H / img.height);
  const w = img.width * scale;
  const h = img.height * scale;
  ctx.drawImage(img, (W - w) / 2, (H - h) / 2, w, h);
}

function drawMinimal(ctx: CanvasRenderingContext2D, { img, entry, dateLabel, streak }: DrawArgs) {
  ctx.clearRect(0, 0, W, H);
  const onPhoto = Boolean(img);

  if (img) {
    coverImage(ctx, img);
    const g = ctx.createLinearGradient(0, H * 0.45, 0, H);
    g.addColorStop(0, "rgba(0,0,0,0)");
    g.addColorStop(1, "rgba(0,0,0,0.62)");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
  } else {
    ctx.fillStyle = PAPER;
    ctx.fillRect(0, 0, W, H);
  }

  const fg = onPhoto ? PAPER : INK;
  const sub = onPhoto ? "rgba(250,246,238,0.82)" : "#6e665c";

  // wordmark top-left
  ctx.fillStyle = sub;
  ctx.font = "italic 36px 'Newsreader', serif";
  ctx.textAlign = "left";
  ctx.fillText("brewdiary", 72, 96);

  // streak line
  if (streak > 0) {
    ctx.fillStyle = ACCENT;
    ctx.font = "600 26px 'Hanken Grotesk', sans-serif";
    ctx.fillText(`NIGHT ${streak}`, 72, H - 232);
  }

  // drink (serif, large, wrap to 2 lines)
  ctx.fillStyle = fg;
  ctx.font = "600 92px 'Newsreader', serif";
  const lines = wrap(ctx, entry.drink, W - 144, 2);
  let y = H - 150 - (lines.length - 1) * 88;
  for (const line of lines) {
    ctx.fillText(line, 72, y);
    y += 88;
  }

  // mood · date
  ctx.fillStyle = sub;
  ctx.font = "italic 40px 'Newsreader', serif";
  const meta = [entry.mood, dateLabel].filter(Boolean).join("  ·  ");
  ctx.fillText(meta, 72, H - 80);

  // mark dot bottom-right
  mark(ctx, W - 96, H - 96, onPhoto ? PAPER : INK);
}

function drawPoster(ctx: CanvasRenderingContext2D, { img, entry, dateLabel, streak }: DrawArgs) {
  ctx.clearRect(0, 0, W, H);

  // ink color-block base
  ctx.fillStyle = INK;
  ctx.fillRect(0, 0, W, H);

  if (img) {
    // duotone-ish: draw photo in the lower 55%, multiply amber over it
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

  // top: eyebrow + big title
  ctx.textAlign = "left";
  ctx.fillStyle = ACCENT;
  ctx.font = "600 30px 'Hanken Grotesk', sans-serif";
  ctx.fillText("BREWDIARY", 72, 120);

  ctx.fillStyle = PAPER;
  ctx.font = "700 116px 'Newsreader', serif";
  const lines = wrap(ctx, entry.drink, W - 144, 3);
  let y = 240;
  for (const line of lines) {
    ctx.fillText(line, 72, y);
    y += 108;
  }

  // mosaic motif row
  const mx = 72;
  const my = y + 24;
  const alphas = [0.2, 0.5, 0.85, 0.35, 0.65, 0.25, 0.9];
  alphas.forEach((a, i) => {
    ctx.fillStyle = `rgba(250,246,238,${a})`;
    ctx.fillRect(mx + i * 46, my, 34, 34);
  });

  // bottom strip: mood · date · streak
  ctx.fillStyle = PAPER;
  ctx.font = "italic 44px 'Newsreader', serif";
  ctx.fillText(entry.mood ?? "", 72, H - 120);

  ctx.fillStyle = "rgba(250,246,238,0.7)";
  ctx.font = "600 28px 'Hanken Grotesk', sans-serif";
  const meta = [dateLabel.toUpperCase(), streak > 0 ? `NIGHT ${streak}` : ""].filter(Boolean).join("   ·   ");
  ctx.fillText(meta, 72, H - 72);
}

function wrap(ctx: CanvasRenderingContext2D, text: string, maxW: number, maxLines: number): string[] {
  const words = text.split(" ");
  const lines: string[] = [];
  let line = "";
  for (const word of words) {
    const test = line ? `${line} ${word}` : word;
    if (ctx.measureText(test).width > maxW && line) {
      lines.push(line);
      line = word;
      if (lines.length === maxLines - 1) break;
    } else {
      line = test;
    }
  }
  if (line && lines.length < maxLines) lines.push(line);
  // truncate overflow with an ellipsis
  if (lines.length === maxLines) {
    let last = lines[maxLines - 1];
    while (ctx.measureText(`${last}…`).width > maxW && last.length > 1) last = last.slice(0, -1);
    if (words.join(" ") !== lines.join(" ")) lines[maxLines - 1] = `${last}…`;
  }
  return lines;
}

function mark(ctx: CanvasRenderingContext2D, x: number, y: number, color: string) {
  ctx.globalAlpha = 0.7;
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y, 8, 0, Math.PI * 2);
  ctx.fill();
  ctx.globalAlpha = 1;
}
