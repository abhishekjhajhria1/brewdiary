"use client";

// A QR code drawn as SVG, on white, here in the page — no network, no image service.
import { useMemo } from "react";
import qrcode from "qrcode-generator";

export function QrSvg({ data, size = 240, label }: { data: string; size?: number; label: string }) {
  const { path, dim } = useMemo(() => {
    const qr = qrcode(0, "M");
    qr.addData(data);
    qr.make();
    const n = qr.getModuleCount();
    const quiet = 4;
    let d = "";
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (qr.isDark(r, c)) d += `M${c + quiet} ${r + quiet}h1v1h-1z`;
    return { path: d, dim: n + quiet * 2 };
  }, [data]);
  return (
    <svg role="img" aria-label={label} data-qr={data} width={size} height={size} viewBox={`0 0 ${dim} ${dim}`} shapeRendering="crispEdges" className="rounded-ctl">
      <rect width={dim} height={dim} fill="#ffffff" />
      <path d={path} fill="#111111" />
    </svg>
  );
}
