// Shared paint primitives for the export cards (ShareCard = an entry,
// ScoreCard = a score). Export-only palette: warm paper, ink, one amber — the
// artifact keeps this look whichever theme the app is wearing.
export const PAPER = "#faf6ee";
export const INK = "#1b1714";
export const ACCENT = "#b8742a";
export const W = 1080;
export const H = 1350;

export function loadImage(url: string): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = url;
  });
}

export function coverImage(ctx: CanvasRenderingContext2D, img: HTMLImageElement) {
  const scale = Math.max(W / img.width, H / img.height);
  const w = img.width * scale;
  const h = img.height * scale;
  ctx.drawImage(img, (W - w) / 2, (H - h) / 2, w, h);
}

export function wrap(ctx: CanvasRenderingContext2D, text: string, maxW: number, maxLines: number): string[] {
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

export function mark(ctx: CanvasRenderingContext2D, x: number, y: number, color: string) {
  ctx.globalAlpha = 0.7;
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y, 8, 0, Math.PI * 2);
  ctx.fill();
  ctx.globalAlpha = 1;
}

/** Wait for webfonts before painting, so the canvas never bakes in a fallback. */
export async function fontsReady() {
  try {
    await (document as Document & { fonts?: FontFaceSet }).fonts?.ready;
  } catch {
    /* fonts optional */
  }
}

/** Share the canvas as a PNG (Web Share on mobile), else fall back to a download. */
export async function shareCanvas(canvas: HTMLCanvasElement | null, filename: string, text: string) {
  const blob = await new Promise<Blob | null>((resolve) => {
    if (!canvas) return resolve(null);
    canvas.toBlob((b) => resolve(b), "image/png");
  });
  if (!blob) return;

  const file = new File([blob], filename, { type: "image/png" });
  const nav = navigator as Navigator & { canShare?: (d: ShareData) => boolean };
  if (nav.canShare?.({ files: [file] })) {
    try {
      await nav.share({ files: [file], title: "brewdiary", text });
      return;
    } catch {
      /* cancelled or unsupported — fall through to a download */
    }
  }
  downloadBlob(blob, filename);
}

export async function downloadCanvas(canvas: HTMLCanvasElement | null, filename: string) {
  const blob = await new Promise<Blob | null>((resolve) => {
    if (!canvas) return resolve(null);
    canvas.toBlob((b) => resolve(b), "image/png");
  });
  if (blob) downloadBlob(blob, filename);
}

function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

export const canShareFiles = () => typeof navigator !== "undefined" && "canShare" in navigator;
