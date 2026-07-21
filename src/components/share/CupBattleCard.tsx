"use client";

// CupBattleCard — share a TEAM CUP the way ScoreCard shares a score. Same
// 1080×1350 export scaffold, same warm export palette (./canvas).
//
// What it will and won't say (the house rules, on a poster):
//   • the two sides, their scores and the tug-of-war bar — scored on the cup's
//     honest axis (new families / places / dry-day runs…), COUNTS only.
//   • NEVER a volume, never a spend, never a named loser — the caption says the
//     axis out loud, because "what the number means" is the brag.
import { useCallback, useEffect, useRef, useState } from "react";
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
  wrap,
} from "./canvas";

export interface CupBattle {
  cupName: string;
  /** Human label of the scoring axis, e.g. "New families". */
  axis: string;
  /** e.g. "3 days left" / "ended" — the window, worn as a badge. */
  status: string;
  teamA: string;
  teamB: string;
  scoreA: number;
  scoreB: number;
  playersA: number;
  playersB: number;
}

export function CupBattleCard({ battle, onClose }: { battle: CupBattle; onClose: () => void }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [rendering, setRendering] = useState(true);

  const draw = useCallback(async () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    setRendering(true);
    await fontsReady();
    drawBattle(ctx, battle);
    setRendering(false);
  }, [battle]);

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

  const file = "brewdiary-cup.png";
  const download = () => downloadCanvas(canvasRef.current, file);
  const share = () =>
    shareCanvas(
      canvasRef.current,
      file,
      `${battle.teamA} ${battle.scoreA} — ${battle.scoreB} ${battle.teamB} · ${battle.cupName}`,
    );

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

// ─── the one template — a match poster ──────────────────────────────
function drawBattle(ctx: CanvasRenderingContext2D, b: CupBattle) {
  ctx.clearRect(0, 0, W, H);
  ctx.fillStyle = INK;
  ctx.fillRect(0, 0, W, H);

  ctx.textAlign = "left";
  ctx.fillStyle = ACCENT;
  ctx.font = "600 30px 'Hanken Grotesk', sans-serif";
  ctx.fillText("BREWDIARY · CUP", 72, 120);

  // the cup's name — the headline
  ctx.fillStyle = PAPER;
  ctx.font = "italic 84px 'Newsreader', serif";
  const nameLines = wrap(ctx, b.cupName, W - 144, 2);
  nameLines.forEach((line, i) => ctx.fillText(line, 72, 240 + i * 96));
  const afterName = 240 + nameLines.length * 96;

  ctx.fillStyle = "rgba(250,246,238,0.7)";
  ctx.font = "600 28px 'Hanken Grotesk', sans-serif";
  ctx.fillText(`${b.axis.toUpperCase()}   ·   ${b.status.toUpperCase()}`, 72, afterName + 8);

  // the two scores, huge, facing each other
  const midY = H * 0.56;
  const total = b.scoreA + b.scoreB;
  const aLeads = b.scoreA > b.scoreB;
  const bLeads = b.scoreB > b.scoreA;

  ctx.textAlign = "left";
  ctx.fillStyle = aLeads ? ACCENT : PAPER;
  ctx.font = "700 200px 'Newsreader', serif";
  ctx.fillText(String(b.scoreA), 72, midY);

  ctx.textAlign = "right";
  ctx.fillStyle = bLeads ? ACCENT : PAPER;
  ctx.fillText(String(b.scoreB), W - 72, midY);

  ctx.textAlign = "left";
  ctx.fillStyle = "rgba(250,246,238,0.82)";
  ctx.font = "600 34px 'Hanken Grotesk', sans-serif";
  ctx.fillText(wrap(ctx, b.teamA, W / 2 - 120, 1)[0] ?? "", 72, midY + 64);
  ctx.textAlign = "right";
  ctx.fillText(wrap(ctx, b.teamB, W / 2 - 120, 1)[0] ?? "", W - 72, midY + 64);

  ctx.font = "500 26px 'Hanken Grotesk', sans-serif";
  ctx.fillStyle = "rgba(250,246,238,0.55)";
  ctx.textAlign = "left";
  ctx.fillText(`${b.playersA} ${b.playersA === 1 ? "player" : "players"}`, 72, midY + 112);
  ctx.textAlign = "right";
  ctx.fillText(`${b.playersB} ${b.playersB === 1 ? "player" : "players"}`, W - 72, midY + 112);

  // the tug-of-war bar
  const barY = midY + 190;
  const barW = W - 144;
  const share = total > 0 ? b.scoreA / total : 0.5;
  ctx.textAlign = "left";
  ctx.fillStyle = "rgba(250,246,238,0.14)";
  ctx.fillRect(72, barY, barW, 26);
  ctx.fillStyle = ACCENT;
  ctx.fillRect(72, barY, barW * share, 26);

  // the honest footnote — what the numbers are, said out loud
  ctx.fillStyle = "rgba(250,246,238,0.6)";
  ctx.font = "italic 34px 'Newsreader', serif";
  const foot = wrap(ctx, `Scored on ${b.axis.toLowerCase()} — nobody is ranked by what they drank.`, W - 240, 2);
  foot.forEach((line, i) => ctx.fillText(line, 72, H - 140 + i * 44));

  mark(ctx, W - 96, H - 96, PAPER);
}
