"use client";

// The QR code a bar puts on the table.
//
// Bars told us (loudly, in every piece of research) that the thing they need is
// "ten seconds at the counter" and NO extra hardware. Typing an 8-character code
// into an app while holding a drink is the friction that kills a feature like
// this. A QR is the whole onboarding.
//
// Rendered to a canvas locally — no network call, no image service, nothing that
// can be down when the bar is busy. Printable: the download gives a big white
// card you can stick on a table.
import { useCallback, useEffect, useRef, useState } from "react";
import qrcode from "qrcode-generator";

export function RoomQr({ url, code, onClose }: { url: string; code: string; onClose: () => void }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [ready, setReady] = useState(false);

  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    // Type 0 = "pick the smallest size that fits"; M = ~15% error correction, which
    // survives a beer ring on the card.
    const qr = qrcode(0, "M");
    qr.addData(url);
    qr.make();

    const modules = qr.getModuleCount();
    const quiet = 4; // the mandatory quiet zone — without it, scanners struggle
    const size = 720;
    const scale = Math.floor(size / (modules + quiet * 2));
    const dim = scale * (modules + quiet * 2);

    canvas.width = dim;
    canvas.height = dim + 96; // room for the code underneath

    // Always paint on WHITE, whatever theme the dashboard is in — a dark QR on a
    // dark card does not scan.
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.fillStyle = "#000000";
    for (let r = 0; r < modules; r++) {
      for (let c = 0; c < modules; c++) {
        if (qr.isDark(r, c)) {
          ctx.fillRect((c + quiet) * scale, (r + quiet) * scale, scale, scale);
        }
      }
    }

    ctx.fillStyle = "#000000";
    ctx.textAlign = "center";
    ctx.font = "600 34px 'Hanken Grotesk', sans-serif";
    ctx.fillText(`Join with code ${code}`, dim / 2, dim + 40);
    ctx.font = "24px 'Hanken Grotesk', sans-serif";
    ctx.fillStyle = "#666666";
    ctx.fillText("brewdiary", dim / 2, dim + 76);

    setReady(true);
  }, [url, code]);

  useEffect(() => {
    draw();
  }, [draw]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  function download() {
    const c = canvasRef.current;
    if (!c) return;
    c.toBlob((blob) => {
      if (!blob) return;
      const u = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = u;
      a.download = `brewdiary-room-${code}.png`;
      a.click();
      URL.revokeObjectURL(u);
    }, "image/png");
  }

  return (
    <div className="fixed inset-0 z-60 flex flex-col items-center justify-center gap-4 bg-ink/50 p-5">
      <button aria-label="Close" onClick={onClose} className="absolute inset-0" />

      <div className="relative flex w-full max-w-xs flex-col items-center gap-4">
        <canvas ref={canvasRef} className="w-full rounded-tile bg-white shadow-[0_8px_40px_rgba(0,0,0,0.35)]" />

        <p className="text-center text-xs leading-relaxed text-paper/80">
          Put this on the tables. Guests scan it to join tonight&apos;s room — no typing, no app store detour.
        </p>

        <div className="flex w-full gap-2">
          <button
            onClick={download}
            disabled={!ready}
            className="flex-1 rounded-ctl bg-accent py-3 text-sm font-medium text-accent-contrast transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            Download to print
          </button>
          <button
            onClick={onClose}
            className="rounded-ctl border border-paper/40 px-4 py-3 text-sm text-paper transition-colors hover:bg-paper/10"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
