// What a QR code or an NFC tag can carry — the twin of packages/brewdiary_core/lib/links.dart
// (the same test cases in tests/scanCodes.test.ts):
//
//   • a table's or pickup point's link   https://bwdy.site/t/<code>      (051, 059)
//   • a venue's menu                     https://bwdy.site/m/<slug>      (042)
//   • the ready board                    https://bwdy.site/ready/<code>  (059)
//   • a guest card                       bwdy:g:<CODE>                    (056)
//   • a shopping list                    bwdy:l:<slug>:<item>.<qty>,…     (059)
//
// A guest card and a list are not links on purpose: a camera that isn't ours shows them as
// text and opens nothing. A list names products and quantities, never who.

export function readyUrl(code: string, origin = "https://bwdy.site"): string {
  return `${origin.replace(/\/$/, "")}/ready/${code}`;
}

const tableCode = /^[0-9a-z]{8}$/;
const slugRe = /^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])$/;
const guestCode = /^[A-HJ-NP-Z2-9]{6}$/;

/** What a guest card's QR holds. */
export function guestCardQr(code: string): string {
  return `bwdy:g:${code.trim().toUpperCase()}`;
}

/** A scanned guest card (or the 6 letters typed) → the code, or null. */
export function guestCodeFromScan(raw: string): string | null {
  let s = raw.trim().toUpperCase();
  if (s.startsWith("BWDY:G:")) s = s.slice(7);
  return guestCode.test(s) ? s : null;
}

// ── a shopping list ─────────────────────────────────────────────────────────
export const MAX_LIST_LINES = 40;

export interface ListLine {
  productId: string;
  qty: number;
}

function toB64Url(bytes: number[]): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  let out = "";
  for (let i = 0; i < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
    const left = bytes.length - i;
    out += chars[(n >> 18) & 63] + chars[(n >> 12) & 63] + (left > 1 ? chars[(n >> 6) & 63] : "") + (left > 2 ? chars[n & 63] : "");
  }
  return out;
}

function fromB64Url(s: string): number[] | null {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  const bytes: number[] = [];
  let buf = 0;
  let bits = 0;
  for (const c of s) {
    const v = chars.indexOf(c);
    if (v < 0) return null;
    buf = (buf << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((buf >> bits) & 255);
    }
  }
  return bytes;
}

/** A uuid in 22 characters (base64url, no padding): a shorter QR scans faster. */
export function packId(uuid: string): string {
  const hex = uuid.replace(/-/g, "").toLowerCase();
  if (!/^[0-9a-f]{32}$/.test(hex)) throw new Error(`not a uuid: ${uuid}`);
  const bytes: number[] = [];
  for (let i = 0; i < 32; i += 2) bytes.push(parseInt(hex.slice(i, i + 2), 16));
  return toB64Url(bytes);
}

export function unpackId(packed: string): string | null {
  if (!/^[A-Za-z0-9_-]{22}$/.test(packed)) return null;
  const bytes = fromB64Url(packed);
  if (!bytes || bytes.length !== 16) return null;
  const hex = bytes.map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/** What a list's QR holds. Quantities 1–99; the same product twice adds up. */
export function shopListQr(slug: string, lines: ListLine[]): string {
  const merged = new Map<string, number>();
  for (const l of lines) {
    if (l.qty < 1) continue;
    merged.set(l.productId, Math.min(99, Math.max(1, (merged.get(l.productId) ?? 0) + l.qty)));
  }
  const parts = [...merged.entries()].slice(0, MAX_LIST_LINES).map(([id, q]) => `${packId(id)}.${q}`);
  return `bwdy:l:${slug.trim().toLowerCase()}:${parts.join(",")}`;
}

export function parseShopList(raw: string): { slug: string; lines: ListLine[] } | null {
  const s = raw.trim();
  if (!s.startsWith("bwdy:l:")) return null;
  const rest = s.slice(7);
  const i = rest.indexOf(":");
  if (i < 0) return null;
  const slug = rest.slice(0, i);
  if (!slugRe.test(slug)) return null;
  const lines: ListLine[] = [];
  for (const part of rest.slice(i + 1).split(",")) {
    if (!part) continue;
    const dot = part.lastIndexOf(".");
    if (dot < 0) return null;
    const id = unpackId(part.slice(0, dot));
    const qty = /^\d+$/.test(part.slice(dot + 1)) ? Number(part.slice(dot + 1)) : NaN;
    if (!id || !Number.isInteger(qty) || qty < 1 || qty > 99) return null;
    lines.push({ productId: id, qty });
    if (lines.length > MAX_LIST_LINES) return null;
  }
  return lines.length ? { slug, lines } : null;
}

// ── one scan, any of the above ──────────────────────────────────────────────
export type ScanKind = "table" | "menu" | "ready" | "guestCard" | "shopList" | "unknown";

function ourHost(host: string): boolean {
  const h = host.toLowerCase();
  return h === "bwdy.site" || h.endsWith(".bwdy.site") || h === "localhost" || h === "127.0.0.1";
}

export function classifyScan(raw: string): { kind: ScanKind; value: string | null } {
  const s = raw.trim();
  if (s.toLowerCase().startsWith("bwdy:g:")) {
    const c = guestCodeFromScan(s);
    return { kind: c ? "guestCard" : "unknown", value: c };
  }
  if (s.startsWith("bwdy:l:")) return { kind: parseShopList(s) ? "shopList" : "unknown", value: null };
  let u: URL;
  try {
    u = new URL(s);
  } catch {
    return { kind: "unknown", value: null };
  }
  if (!(u.protocol === "https:" || u.protocol === "http:") || !ourHost(u.hostname)) return { kind: "unknown", value: null };
  const seg = u.pathname.split("/").filter(Boolean);
  if (seg.length >= 2) {
    const v = seg[1].trim().toLowerCase();
    if (seg[0] === "t" && tableCode.test(v)) return { kind: "table", value: v };
    if (seg[0] === "m" && slugRe.test(v)) return { kind: "menu", value: v };
    if (seg[0] === "ready" && tableCode.test(v)) return { kind: "ready", value: v };
  }
  return { kind: "unknown", value: null };
}
